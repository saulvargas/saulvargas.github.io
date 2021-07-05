#!/usr/bin/env bash

INSTALL_DIR="$HOME/.set_aws_credentials"
SCRIPT_PATH="$INSTALL_DIR/set_aws_credentials.py"
BIN_PATH="$HOME/.local/bin"
COMMAND_PATH="$BIN_PATH/set_aws_credentials"

# check that python3, pip3 and virtualenvs are available
if ! command -v python3 &>/dev/null; then
  echo "ERROR: python3 could not be found"
  echo "       you need to install python!"
  exit 1
fi
if ! command -v pip3 &>/dev/null; then
  echo "ERROR: pip3 could not be found"
  exit 1
fi
if ! pip3 freeze | grep -q virtualenv; then
  echo "ERROR: virtualenv is not installed"
  echo "       run \"pip3 install virtualenv\" first and try again"
  exit 1
fi

mkdir -p "$INSTALL_DIR"

cat >"$SCRIPT_PATH" <<EOF
import argparse
import functools
import os
import subprocess

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
def main(*, profile: str) -> None:
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


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("profile")
    args = parser.parse_args()

    main(profile=args.profile)

EOF

python3 -m virtualenv -q "$INSTALL_DIR/venv"
. "$INSTALL_DIR/venv/bin/activate"
pip3 -q install --upgrade pip
pip3 -q install boto3
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

echo "$ set_aws_credentials <profile_name>"
echo "and check that the AWS environment variables are set up with"
echo "$ env | grep AWS_"
echo "enjoy!"
