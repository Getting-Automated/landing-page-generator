const fs = require('fs');
const path = require('path');

module.exports = function override(config, env) {
  const configJson = JSON.parse(fs.readFileSync(path.resolve(__dirname, 'public/config.json'), 'utf8'));

  process.env.REACT_APP_TITLE = configJson.seoTitle;
  process.env.REACT_APP_META_DESCRIPTION = configJson.seoDescription;
  process.env.REACT_APP_DOMAIN_URL = `https://${configJson.domainName}/`;
  process.env.REACT_APP_HERO_TITLE = configJson.title;

  return config;
};