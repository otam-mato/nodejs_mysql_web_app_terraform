// define default config, but allow overrides from ENV vars
let config = {
  APP_DB_HOST: "localhost",
  APP_DB_USER: "admin",
  APP_DB_PORT: "3306" ,
  APP_DB_PASSWORD: "12345678",
  APP_DB_NAME: "COFFEE"
}

Object.keys(config).forEach(key => {
  if(process.env[key] === undefined){
    console.log(`[NOTICE] Value for key '${key}' not found in ENV, using default value.  See app/config/config.js`)
  } else {
    config[key] = process.env[key]
  }
});

module.exports = config;
