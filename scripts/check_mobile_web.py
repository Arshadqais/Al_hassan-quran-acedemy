"""Verify PWA installability and private-cache isolation against a built website."""
import argparse
import json, tempfile
from pathlib import Path
from playwright.sync_api import sync_playwright
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--url',required=True,help='URL of a locally served Flutter release build')
parser.add_argument('--browser-executable',help='Optional system Chromium executable')
parser.add_argument('--output-dir',type=Path,required=True)
args=parser.parse_args()
base=args.url.rstrip('/')+'/'
args.output_dir.mkdir(parents=True,exist_ok=True)
results=[]
with sync_playwright() as p:
 for label, width, height in [('desktop',1440,1000),('phone',390,844)]:
  profile=tempfile.TemporaryDirectory(prefix='academy-pwa-check-')
  context=p.chromium.launch_persistent_context(profile.name,executable_path=args.browser_executable,headless=True,args=['--no-sandbox'],viewport={'width':width,'height':height},is_mobile=label=='phone',has_touch=label=='phone')
  page=context.new_page(); errors=[]
  page.on('pageerror',lambda error:errors.append(str(error)))
  page.goto(base,wait_until='networkidle',timeout=60000)
  page.wait_for_function('document.getElementById("loading")===null',timeout=30000)
  page.locator('flt-semantics-placeholder').dispatch_event('click')
  page.get_by_role('button',name='Install the academy app',exact=True).click()
  page.get_by_text('Install Al Hassan Academy',exact=True).wait_for()
  page.get_by_text('Android',exact=True).wait_for()
  page.get_by_text('iPhone / iPad',exact=True).wait_for()
  page.screenshot(path=str(args.output_dir/f'pwa-install-{label}.png'))
  page.get_by_role('button',name='Got it',exact=True).click()
  page.wait_for_function('navigator.serviceWorker.controller!==null',timeout=30000)
  assert page.evaluate('navigator.serviceWorker.controller.scriptURL').endswith('/academy-service-worker.js')
  manifest=page.evaluate('async()=>await(await fetch("manifest.json")).json()')
  assert manifest['scope']=='./' and manifest['display']=='standalone'
  for icon in manifest['icons']:
   image=page.evaluate('''async (src)=>{const i=new Image();i.src=src;await i.decode();return [i.naturalWidth,i.naturalHeight]}''',icon['src'])
   assert image==[int(icon['sizes'].split('x')[0])]*2
  session=context.new_cdp_session(page)
  install_errors=session.send('Page.getInstallabilityErrors')
  print(label,'installability:',install_errors)
  assert not install_errors['installabilityErrors'],install_errors
  await_result=page.evaluate('''async()=>{await fetch('private-sentinel?do-not-cache');const out={};for(const key of await caches.keys()){const c=await caches.open(key);out[key]=(await c.keys()).map(r=>r.url)}return out}''')
  assert len(await_result)==1 and all(url.endswith('/offline.html') for urls in await_result.values() for url in urls),await_result
  context.set_offline(True)
  page.goto(base+'?offline-check',wait_until='domcontentloaded')
  page.get_by_role('heading',name="You're offline",exact=True).wait_for()
  page.screenshot(path=str(args.output_dir/f'pwa-offline-{label}.png'))
  context.set_offline(False)
  page.get_by_role('link',name='Try again').click()
  page.wait_for_function('document.getElementById("loading")===null',timeout=30000)
  assert not errors,errors
  results.append({'viewport':label,'install_help':'passed','manifest_and_icons':'passed','chrome_installability':'passed','offline_notice_and_reconnect':'passed','cache_contents':await_result,'javascript_errors':errors})
  context.close(); profile.cleanup()
(args.output_dir/'pwa-validation.json').write_text(json.dumps(results,indent=2))
print(json.dumps(results,indent=2))
