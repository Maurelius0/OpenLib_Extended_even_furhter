const {chromium}=require('playwright');
const fs=require('fs');
const path=require('path');
const root=path.resolve(__dirname,'..');
(async()=>{
const browser=await chromium.launch({executablePath:process.env.READER_CHROMIUM_PATH,headless:true,args:['--no-sandbox']});
const page=await browser.newPage({viewport:{width:412,height:800},hasTouch:true});
const dart=fs.readFileSync(path.join(root,'lib/ui/epub_viewer.dart'),'utf8');
const css=dart.split('<style>')[1].split('</style>')[0].replace('${_fontSize}',20);
const script=fs.readFileSync(path.join(root,'lib/ui/components/epub_pagination.js'),'utf8');
const cover='<svg viewBox="0 0 100 120"><rect width="100" height="120" fill="red"/></svg>';
const sections=[cover, '<h1>Chapter one</h1>'+('<p>Some reading content with enough words to fill several pages. Books are wonderful.</p>'.repeat(28)), '<h1 id="dest">Chapter two</h1>'+('<p>The next chapter has many more words to read.</p>'.repeat(120))];
async function load(body){
 await page.setContent(`<html><head><style>${css}</style></head><body><div id="viewport"><main id="book" class="reader-section">${body}</main></div></body></html>`);
 await page.evaluate(()=>{window.calls=[];window.readerChapter=1;window.flutter_inappwebview={callHandler:(...args)=>window.calls.push(args)}});
 await page.addScriptTag({content:script});await page.evaluate(()=>window.readerRestore(0,false));await page.waitForTimeout(60);
}
await load(sections[1]);
for (const size of [20,30]){
 await page.evaluate(s=>window.readerSettings(s,false),size);await page.waitForTimeout(60);
 const counts=[];for(const body of sections)counts.push((await page.evaluate(b=>window.readerMeasure(b),body)).count);
 if(counts[0]!==1||counts[1]<2||counts[2]<counts[1])throw Error('unexpected counts '+counts);
 const live=await page.evaluate(()=>window.calls.filter(c=>c[0]==='reader').at(-1)[1]);
 if(live.count!==counts[1])throw Error('offscreen and live count differ '+JSON.stringify({counts,live}));
 for(let p=0;p<counts[1];p++){
  await page.evaluate(p=>window.readerGoPage(p),p);
  const current=await page.evaluate(()=>window.calls.filter(c=>c[0]==='reader').at(-1)[1]);
  if(current.page!==p)throw Error('wrong page');
 }
 if(await page.locator('.reader-section').count()!==1)throw Error('measurement nodes leaked');
 console.log('PASS section counts at font '+size+': '+counts.join(', '));
}
await page.setViewportSize({width:780,height:412});await page.waitForTimeout(150);
const rotated=await page.evaluate(b=>window.readerMeasure(b),sections[1]);
const live=await page.evaluate(()=>window.calls.filter(c=>c[0]==='reader').at(-1)[1]);
if(rotated.count!==live.count||rotated.layout!==live.layout)throw Error('rotation mismatch');
await page.evaluate(()=>window.readerGoPage(0));
await page.mouse.click(770,180);
if(await page.evaluate(()=>window.calls.filter(c=>c[0]==='reader').at(-1)[1].page)!==1)throw Error('tap navigation lost');
await page.mouse.click(390,180);
if(!await page.evaluate(()=>window.calls.some(c=>c[0]==='controls')))throw Error('middle tap lost');
console.log('PASS resized counts, exact page seeking, tap navigation and middle control toggle');
await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
