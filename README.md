Build your own complete Magento Git repository using this script.

~~~~
mkdir -p /usr/src/magento
cd /usr/src/magento
git clone https://github.com/sonassi/magento-ce-builder
cd magento-ce-builder
~~~~

Copy `settings.conf.default` to `settings.conf` and define the runtime settings.

Then execute the script.

~~~~
bash build.sh
~~~~
