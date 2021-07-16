#!/usr/bin/env bash

INSTALL_DIR="$HOME/.set_aws_credentials"
SCRIPT_PATH="$INSTALL_DIR/set_aws_credentials.py"
BIN_PATH="$HOME/.local/bin"
COMMAND_PATH="$BIN_PATH/set_aws_credentials"

# check that python3, pip3 and virtualenv are available
if ! command -v python3 &>/dev/null; then
  echo "ERROR: python3 could not be found, please install python."
  exit 1
fi
if ! command -v pip3 &>/dev/null; then
  echo "ERROR: pip3 could not be found"
  exit 1
fi
if ! pip3 freeze | grep -q virtualenv; then
  echo "ERROR: virtualenv is not installed, please run \"pip3 install virtualenv\""
  exit 1
fi
if ! command -v aws &>/dev/null; then
  echo "ERROR: aws cli is not installed, install: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
  exit 1
fi
if ! [[ $(aws --version) =~ ^aws-cli/2\. ]]; then
  echo "ERROR: aws cli is probably outdated, update: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
  exit 1
fi


mkdir -p "$INSTALL_DIR"

cat >"$SCRIPT_PATH" <<EOF
import argparse
import configparser
import functools
import os
import subprocess
from pathlib import Path

import boto3
import botocore.exceptions


def retry_with_sso_login(f):
    @functools.wraps(f)
    def wrapper(**kwargs):
        try:
            return f(**kwargs)
        except botocore.exceptions.UnauthorizedSSOTokenError:
            profile = kwargs["profile"]
            subprocess.run(f"aws sso login --profile {profile}", shell=True, check=True)

            return f(**kwargs)

    return wrapper


@retry_with_sso_login
def set_env(*, profile: str) -> None:
    session = boto3.Session(profile_name=profile)
    credentials = session.get_credentials().get_frozen_credentials()

    envvars = dict(
        AWS_DEFAULT_PROFILE=profile,
        AWS_ACCESS_KEY_ID=credentials.access_key,
        AWS_SECRET_ACCESS_KEY=credentials.secret_key,
        AWS_SESSION_TOKEN=credentials.token,
    )
    for var, val in envvars.items():
        os.environ[var] = val

    print(f"STARTING A NEW SHELL WITH AWS CREDENTIALS FOR {profile}")
    shell = os.environ["SHELL"]
    subprocess.run(shell)


def set_file(profiles: list[str]) -> None:
    credentials_path = (Path.home() / ".aws/credentials")
    credentials_path.touch(exist_ok=True)

    credentials = configparser.ConfigParser()
    credentials.read(credentials_path)

    for profile in profiles:
        set_file_profile(credentials=credentials, profile=profile)

    with credentials_path.open("w") as f:
        credentials.write(f)


@retry_with_sso_login
def set_file_profile(*, credentials: configparser.ConfigParser, profile: str) -> None:
    session = boto3.Session(profile_name=profile)
    new_credentials = session.get_credentials().get_frozen_credentials()

    credentials[profile] = {
        "aws_access_key_id": new_credentials.access_key,
        "aws_secret_access_key": new_credentials.secret_key,
        "aws_session_token": new_credentials.token,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("-f", "--file", action="store_true")
    parser.add_argument("profiles", nargs="+")
    args = parser.parse_args()

    if args.file:
        set_file(args.profiles)
    else:
        if len(args.profiles) == 1:
            set_env(profile=args.profiles[0])
        else:
            raise ValueError("cannot setup environment for more than one account")

EOF

python3 -m virtualenv -q "$INSTALL_DIR/venv"
. "$INSTALL_DIR/venv/bin/activate"
python3 -m pip -q install --upgrade pip
python3 -m pip -q install boto3 toml
deactivate

cat >"$COMMAND_PATH" <<EOF
#!/usr/bin/env bash

. "$INSTALL_DIR/venv/bin/activate"
python3 $SCRIPT_PATH "\$@"
deactivate

EOF

chmod +x "$COMMAND_PATH"

if ! command -v "$COMMAND_PATH"; then
  echo "WARNING: set_aws_credentials has been installed in $BIN_PATH, but $BIN_PATH is not part of your \$PATH. Fix this, and then try running:"
else
  echo "SUCCESS: set_aws_credentials has been installed, try running"
fi

echo "     $ set_aws_credentials <profile_name>"
echo " and check that the AWS environment variables are set up with"
echo "     $ env | grep AWS_"
echo " or"
echo "     $ set_aws_credentials -f <profile_name>"
echo " and then"
echo "     $ cat ~/.aws/credentials"
echo ""
echo "Enjoy!"
