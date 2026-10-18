const {chromium}=require('playwright');
const fs=require('fs'),path=require('path'),assert=require('assert');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.READER_CHROMIUM_PATH,headless:true,args:['--no-sandbox']});
 try {
  const page=await browser.newPage();
  const src='data:image/svg+xml,'+encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10"/></svg>');
  await page.setContent(`<div id="viewport"><main id="book" class="reader-section">
   <img id="explicit" src="${src}" title="Debt cycle" alt="Image">
   <figure><img id="caption" src="${src}" alt="Image"><figcaption>Figure 2: <em>Money</em> and credit</figcaption></figure>
   <p id="label">Reserve currency shares</p><img id="labelled" src="${src}" aria-labelledby="label">
   <svg id="svg"><title>Empire strength</title><rect id="svg-child" width="10" height="10"/></svg>
   <img id="alternate" src="${src}" alt="Gold holdings by year">
   <img id="generic" src="${src}" alt="Image">
   <img id="filename" src="${src}" alt="image003.png">
   <figure><img id="fallback" src="${src}" title="Image"><figcaption>A real caption</figcaption></figure>
  </main></div>`);
  await page.evaluate(()=>{window.calls=[];window.flutter_inappwebview={callHandler:(...v)=>window.calls.push(v)}});
  await page.addScriptTag({content:fs.readFileSync(path.resolve(__dirname,'../lib/ui/components/epub_pagination.js'),'utf8')});
  for(const [id,expected] of Object.entries({explicit:'Debt cycle',caption:'Figure 2: Money and credit',labelled:'Reserve currency shares','svg-child':'Empire strength',alternate:'Gold holdings by year',generic:'',filename:'',fallback:'A real caption'})){
   await page.evaluate(id=>{window.calls=[];document.getElementById(id).dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,cancelable:true}));},id);
   const call=await page.evaluate(()=>window.calls.find(c=>c[0]==='image'));
   assert(call, id+' did not open');assert(call[1].startsWith('data:image/'));assert.equal(call[2],expected,id);
   // Ignore the intentional long-press debounce before exercising the next image.
   await page.waitForTimeout(820);
  }
  console.log('PASS image titles, figure captions, accessibility labels, SVG titles and useful alt text; generic placeholders stay hidden');
 } finally {await browser.close()}
})().catch(e=>{console.error(e);process.exit(1)});
