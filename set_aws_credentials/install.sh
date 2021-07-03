#!/usr/bin/env bash

INSTALL_DIR="$HOME/.set_aws_credentials"
SCRIPT_PATH="$INSTALL_DIR/set_aws_credentials.py"
COMMAND_PATH="$HOME/.local/bin/set_aws_credentials"

mkdir -p "$INSTALL_DIR"

cat > "$SCRIPT_PATH" << EOF
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

virtualenv -q "$INSTALL_DIR/venv"
. "$INSTALL_DIR/venv/bin/activate"
pip -q install --upgrade pip
pip -q install boto3
deactivate

cat > "$COMMAND_PATH" << EOF
#!/usr/bin/env bash

. "$INSTALL_DIR/venv/bin/activate"
python $SCRIPT_PATH "\$@"
deactivate

EOF

chmod +x "$COMMAND_PATH"

echo "set_aws_credentials has been installed, try running"
echo "$ set_aws_credentials <profile_name>"
echo "and check that the AWS environment variables are set up with"
echo "$ env | grep AWS_"
echo "enjoy!"
