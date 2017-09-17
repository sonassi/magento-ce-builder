#!/bin/bash

umask 022

if [ -f "settings.conf" ]; then
  . settings.conf
else
  echo "Error: Configuration file, settings.conf, cannot be found"
  exit 1
fi

[[ "$GIT_NAME" == "" ]] || git config --global user.name "$GIT_NAME"
[[ "$GIT_EMAIL" == "" ]] || git config --global user.email "$GIT_EMAIL"

[[ "$REPO_REMOTE" == "" ]] && echo "Error: Repository is not defined" && exit 2

ASSET_URL="https://github.com/sonassi/magento-downloads/raw/master"
START_DIR="$(pwd)"

# Clean up previous runs
[ -d "magento-ce-builder" ] && rm -rf magento-ce-builder/repo magento-ce-builder/versions

# Perform initial check in
mkdir -p magento-ce-builder/repo
cd magento-ce-builder/repo
git init
git remote add origin $REPO_REMOTE
cd ../

function download_release()
{
  local VERS FORMAT FILENAME

  VERS="$1"
  FORMAT="$2"
  FILENAME=$(printf "$FORMAT" "$VERS")

  if [ -f "$DOWNLOADS_DIR/$FILENAME" ]; then
    cp $DOWNLOADS_DIR/$FILENAME magento-$VERS.zip
    return $?
  fi

  wget --no-check-certificate -S --spider "$ASSET_URL/$FILENAME" 2>&1 | grep -q "Remote file exists"
  if [ $? -eq 0 ]; then
    wget --no-check-certificate -qO magento-$VERS.zip $ASSET_URL/$FILENAME
    return 0
  fi

  return 1
}

function process_release()
{
  local VERS COUNT

  VERS="$1"
  COUNT="$2"

  case ${VERS:0:1} in
    1)
      FORMAT="magento-%s.zip"
      ;;
    2)
      FORMAT="Magento-CE-%s.zip"
      ;;
  esac

  # Check to see if tag alreayd exists for release
  if echo "$REMOTE_TAGS" | grep -qE "^$VERS\$"; then
    echo -e "\n >> Skipping $VERS"
    continue
  fi

  # This is to work around the bug of some Magento downloads not being inside a directory called magento
  cd $START_DIR/magento-ce-builder
  [ -d "magento" ] && rm -rf magento
  mkdir -p magento
  cd magento

  echo -ne "\n >> Downloading $VERS"
  download_release "$VERS" "$FORMAT"
  echo " OK"

  echo -n " >> Extracting"
  unzip -o -qq magento-$VERS.zip || return 1
  [ -d "magento" ] && mv magento/* . >/dev/null 2>&1
  [ -d "magento" ] && mv magento/.htaccess* . >/dev/null 2>&1
  rm -rf magento magento-$VERS.zip
  echo " OK"

  echo -n " >> Committing changes"
  cd $START_DIR/magento-ce-builder/repo

  if [ $COUNT -eq 0 ]; then
    TAG="master"
    git pull origin $TAG >/dev/null 2>&1
  elif [ $COUNT -gt 0 ]; then
    TAG=$VERS
    git push origin :refs/tags/$TAG >/dev/null 2>&1
  fi
  rsync -a --delete ../magento/ ../repo/ --exclude="/.git"
  git add * .htaccess* >/dev/null 2>&1
  git commit -am "Version $VERS" >/dev/null 2>&1
  git tag $VERS >/dev/null 2>&1
  echo " OK"

  echo -n " >> Pushing $VERS"
  git push origin $TAG >/dev/null 2>&1
  echo " OK"

  cd $START_DIR/magento-ce-builder

  return 0
}

# Parse Magento's site for a list of current releases
wget --no-check-certificate -qO - http://www.magentocommerce.com/download | \
  ack-grep '>(magento\-|Magento Community Edition )([0-9.]+)\.zip ' --output='$2' | \
  sort -V > versions

REMOTE_TAGS=$( cd $START_DIR/magento-ce-builder/repo; git ls-remote --tags origin | ack-grep 'tags/([0-9.]+)' --output='$1' )
COUNT=0
while read VERS; do
  process_release $VERS $COUNT
  COUNT=$(( COUNT + 1 ))
done < versions

# Cleanup
cd ${START_DIR}
rm -rf magento-ce-builder