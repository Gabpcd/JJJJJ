// Thin adapter around the pinned Playwright JSON reporter. The original private
// report stays private. Only fixed stage/code enums enter its closedDiagnostic.
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { projectBrowserDiagnostic } from './contract.mjs';
const require=createRequire(import.meta.url);
const root=dirname(require.resolve('playwright/package.json'));
const JSONReporter=require(join(root,'lib/reporters/json.js')).default;
export default class ClosedJsonReporter extends JSONReporter {
 _serializeTestResult(result,test) {
  return {...super._serializeTestResult(result,test),closedDiagnostic:projectBrowserDiagnostic(result)};
 }
}
