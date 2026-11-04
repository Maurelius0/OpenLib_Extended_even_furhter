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

await page.setViewportSize({width:412,height:800});
const calls = name => page.evaluate(n => window.calls.filter(c => c[0] === n), name);
for (const target of ['chapter2.xhtml#part', 'https://example.com/book?x=1&y=2']) {
 await load(`<p><a href="#" data-reader-target="${target.replaceAll('&','&amp;')}"><em>Open link</em></a></p>`);
 await page.evaluate(()=>window.calls=[]);
 await page.locator('a em').tap();
 await page.waitForTimeout(80);
 const links=await calls('link');
 if(links.length!==1 || links[0][1]!==target)throw Error('touch link failed '+JSON.stringify(links));
 if((await calls('controls')).length || (await calls('boundary')).length)throw Error('link also triggered page navigation');
}
await load('<a href="#" data-reader-target="chapter2.xhtml#part">Keyboard link</a>');
await page.evaluate(()=>window.calls=[]);
await page.locator('a').focus();await page.keyboard.press('Enter');
if((await calls('link')).length!==1)throw Error('keyboard link activation failed');
// Real taps on ordinary content retain edge navigation and the center menu.
await load(sections[1]);await page.evaluate(()=>window.calls=[]);
await page.touchscreen.tap(402,180);
if((await calls('reader')).at(-1)?.[1].page!==1)throw Error('touch edge page navigation lost');
await page.touchscreen.tap(206,180);
if((await calls('controls')).length!==1)throw Error('touch center menu toggle lost');
console.log('PASS internal and external touch links activate once without turning pages');
const image='data:image/svg+xml,'+encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="80" height="80"><rect width="80" height="80" fill="red"/></svg>');
await load(`<figure><img src="${image}" alt="A chart of the cycle"><figcaption>Cycle illustration</figcaption></figure>`);
await page.evaluate(()=>window.calls=[]);
await page.locator('img').tap();await page.waitForTimeout(80);
let images=await calls('image');
if(images.length!==1 || images[0][1]!==image || images[0][2]!=='Cycle illustration')throw Error('single image tap failed '+JSON.stringify(images));
if((await calls('controls')).length || (await calls('boundary')).length)throw Error('image tap also navigated');
await load('<svg viewBox="0 0 100 120"><title>Vector diagram</title><rect width="100" height="120" fill="red"/></svg>');
await page.evaluate(()=>window.calls=[]);
await page.locator('svg rect').tap();
images=await calls('image');
if(images.length!==1 || !images[0][1].startsWith('data:image/svg+xml;') || images[0][2]!=='Vector diagram')throw Error('SVG tap failed');
await load('<svg viewBox="0 0 100 120"><a href="#" data-reader-target="chapter2.xhtml#part"><rect width="100" height="120" fill="red"/></a></svg>');
await page.evaluate(()=>window.calls=[]);await page.locator('svg rect').tap();
if((await calls('link')).length!==1 || (await calls('image')).length)throw Error('explicit SVG hyperlink lost to image opening');
console.log('PASS single-tap raster and nested SVG image opening with captions');
// A horizontal swipe starting on an image turns the page, without opening it.
await load(`<img src="${image}">`+sections[1]);
await page.evaluate(()=>window.calls=[]);
const cdp=await page.context().newCDPSession(page);
await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:70,y:50}]});
await cdp.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:5,y:50}]});
await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
await page.waitForTimeout(80);
if((await calls('image')).length || (await calls('reader')).at(-1)?.[1].page!==1)throw Error('swipe/image conflict');
// Two fingers never open an illustration or trigger a page turn.
await load(`<img src="${image}">`+sections[1]);await page.evaluate(()=>window.calls=[]);
await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:50,y:50,id:1},{x:80,y:60,id:2}]});
await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
await page.waitForTimeout(80);
if((await calls('image')).length || (await calls('reader')).length)throw Error('multitouch activated content');
console.log('PASS swipe-over-image and multi-finger rejection');
await load('<a id="named"></a>'+sections[1]+'<a name="old-anchor"></a><h2 id="destination">Destination</h2>');
let found=await page.evaluate(()=>window.readerAnchor('destination'));
if(!found || (await calls('reader')).at(-1)[1].page < 1)throw Error('internal anchor did not jump');
if(!await page.evaluate(()=>window.readerAnchor('old-anchor')))throw Error('legacy anchor lookup failed');
if(await page.evaluate(()=>window.readerAnchor('missing')))throw Error('missing anchor reported success');
console.log('PASS id/name anchor navigation and missing-target detection');
await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
