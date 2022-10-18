# oauth2do
Scripts and tools to help with oauth2 services and access token queries

### oauth2-google.sh

This bash script is used to authenticate with Google's OAuth2 service and generate/refresh access tokens.

- Optains google oauth2 tokens and caches it locally
- Silently dumps the access token to stdout, even on intitial authenication  
- Very Useful as 'PassCmd' commands for apps that require oauth2 authentication
- see [mbsync](README.md#mbsync-dot-file) example below
  
Example command line: 
  
  `$ oauth2-google.sh --client_id=123456789.apps.googleusercontent.com --client_secret=abcdefg --scope=https://mail.google.com/`

To create client app id and secret, please refere [Google documentation](https://developers.google.com/adwords/api/docs/guides/authentication)

```
Usage: oauth2-google.sh --option=value ...
Options:
  --client-id      : Client ID
  --client-secret  : Client Secret 
  --login          : Login Hint, optional (email)
  --scope          : Scope (default: https://mail.google.com/)
  --port           : Port (default: 8088)
  --browser        : Browser (default: firefox)
  --store          : Directory to cache token files (default: $HOME/.var/g-oauth2/)
  --help           : This help

Output: access_token
```

#### mbsync 
dot file (mbsyncrc)
```
IMAPAccount gmail
Host imap.gmail.com
User <username>@gmail.com
PassCmd "oauth2-google.sh --client_id=<cid> --client_secret=<cs> --login=<username>@gmail.com  --browser=google-chrome"
SSLType IMAPS
AuthMechs XOAUTH2
```

install SASL xoauth Plugin for mbsync `AuthMechs XOAUTH2` to work
```
# install cyrus sasl libs
sudo dnf install cyrus-sasl cyrus-sasl-devel

# requirements
sudo dnf install libtool automake

# cyrus-sasl-xoauth2 plugin
git clone https://github.com/moriyoshi/cyrus-sasl-xoauth2.git
cd cyrus-sasl-xoauth2
./autogen.sh
./configure
make
sudo make install

# todo: prefix=/usr/lib64 or somthing better than below
sudo mv /usr/lib/sasl2/* /usr/lib64/sasl2/

# validate:
sasl2-shared-mechlist | grep -i xoauth2
```
