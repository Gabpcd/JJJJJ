import {defineConfig,devices} from '@playwright/test';
export default defineConfig({testDir:'./e2e',testMatch:'f1-cloud-navigation.spec.ts',workers:1,retries:0,timeout:60000,
  outputDir:process.env.F1_UI_OUTPUT??'/private/tmp/jolene-f1-cloud-local-navigation',reporter:[['list'],['json',{outputFile:process.env.F1_UI_RESULTS??'/private/tmp/jolene-f1-cloud-local-navigation/results.json'}]],
  use:{baseURL:process.env.F1_UI_BASE_URL??'http://127.0.0.1:18483',locale:'fr-FR',timezoneId:'Europe/Paris',trace:'off',video:'off',screenshot:'off',serviceWorkers:'block'},
  projects:[{name:'iphone',use:{...devices['iPhone 13'],viewport:{width:390,height:844}}},{name:'android',use:{...devices['Pixel 7']}},
    {name:'ipad-portrait',use:{...devices['iPad Pro 11'],viewport:{width:820,height:1180}}},{name:'ipad-paysage',use:{...devices['iPad Pro 11'],viewport:{width:1180,height:820}}},
    {name:'ordinateur',use:{...devices['Desktop Chrome'],viewport:{width:1440,height:900}}}]});
