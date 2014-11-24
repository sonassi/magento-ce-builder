#!/bin/bash

if [ -f "settings.conf" ]; then
  . settings.conf
else
  echo "Error: Configuration file, settings.conf, cannot be found"
  exit 1
fi

[[ "$GIT_NAME" == "" ]] || git config --global user.name "$GIT_NAME"
[[ "$GIT_EMAIL" == "" ]] || git config --global user.email "$GIT_EMAIL"

[[ "$REPO_REMOTE" == "" ]] && echo "Error: Repository is not defined" && exit 2

ASSET_URL="http://www.magentocommerce.com/downloads/assets"
START_DIR="$(pwd)"

# Clean up previous runs
[ -d "magento-ce-builder" ] && rm -rf magento-ce-builder/repo magento-ce-builder/versions

# Perform initial check in
mkdir -p magento-ce-builder/repo
cd magento-ce-builder/repo
git init
git remote add origin $REPO_REMOTE
cd ../

# Parse Magento's site for a list of current releases
wget -qO - http://www.magentocommerce.com/download | ack-grep 'tar.gz">magento-([0-9.]+)\.tar\.gz ' --output='$1' | sort -n > versions

function download_release()
{
  VERS="$1"

  wget --no-check-certificate -S --spider "$ASSET_URL/$VERS/magento-$VERS.tar.gz" 2>&1 | grep -q "Remote file exists"
  if [ $? -eq 0 ]; then
    wget -qO magento-$VERS.tar.gz $ASSET_URL/$VERS/magento-$VERS.tar.gz
    return 0
  fi

  MAIN_VERS=$(echo $VERS | sed -E 's#\.[0-9]$##g')
  wget --no-check-certificate -S --spider "$ASSET_URL/$MAIN_VERS/magento-$VERS.tar.gz" 2>&1 | grep -q "Remote file exists"
  if [ $? -eq 0 ]; then
    wget -qO magento-$VERS.tar.gz $ASSET_URL/$MAIN_VERS/magento-$VERS.tar.gz
    return 0
  fi

  return 1
}

function process_release()
{
  VERS="$1"

  cd $START_DIR/magento-ce-builder

  echo -ne "\n >> Downloading $VERS"
  [ ! -f "magento-$VERS.tar.gz" ] && download_release $VERS
  echo " OK"

  echo -n " >> Extracting"
  tar xfz magento-$VERS.tar.gz || return 1
  echo " OK"

  echo -n " >> Committing changes"
  cd $START_DIR/magento-ce-builder/repo
  git checkout -b $VERS >/dev/null 2>&1
  rsync -a --delete ../magento/ ../repo/ --exclude="/.git"
  git add * .htaccess* >/dev/null 2>&1
  git commit -am "Version $VERS" >/dev/null 2>&1
  echo " OK"

  echo -n " >> Pushing $VERS"
  git push origin $VERS >/dev/null 2>&1
  echo " OK"

  cd $START_DIR/magento-ce-builder
  rm -rf magento

  return 0
}

while read VERS; do
  process_release $VERS || ( rm $START_DIR/magento-ce-builder/magento-$VERS.tar.gz 2>/dev/null; process_release $VERS )
done < versions

# Cleanup
cd ${START_DIR}
rm -rf magento-ce-builder
