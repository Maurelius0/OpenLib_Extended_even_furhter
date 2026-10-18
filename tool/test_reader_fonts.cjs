const {chromium} = require('playwright');
const fs = require('fs'), path = require('path'), assert = require('assert');
const root = path.resolve(__dirname, '..');
(async () => {
 const browser = await chromium.launch({executablePath:process.env.READER_CHROMIUM_PATH,
   headless:true,args:['--no-sandbox']});
 try {
 const page = await browser.newPage({viewport:{width:412,height:800}});
 const errors=[];page.on('pageerror', e=>errors.push(String(e)));
 const dart = fs.readFileSync(path.join(root,'lib/ui/epub_viewer.dart'),'utf8');
 const css = dart.split('<style>')[1].split('</style>')[0].replace('${_fontSize}',20);
 const body = fs.readFileSync(process.env.READER_TEST_HTML,'utf8') +
   '<p id="family-probe" style="font-family:monospace!important">Reader font <em id="emphasis-probe">emphasis</em></p><pre id="code-probe">monospace code</pre>';
 const script = fs.readFileSync(path.join(root,'lib/ui/components/epub_pagination.js'),'utf8');
 await page.setContent(`<html><head><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; font-src data:; style-src 'unsafe-inline'; script-src 'unsafe-inline'"><style>${css}</style></head><body><div id="viewport"><main id="book" class="reader-section">${body}</main></div></body></html>`);
 await page.evaluate(()=>{window.calls=[];window.readerChapter=1;
   window.flutter_inappwebview={callHandler:(...v)=>window.calls.push(v)};});
 await page.addScriptTag({content:script});
 await page.evaluate(async()=>{await document.fonts.ready;
   await Promise.all(Array.from(document.images).map(i=>i.decode().catch(()=>{})));
   window.readerRestore(0,false);});
 await page.evaluate(()=>new Promise(requestAnimationFrame));
 const originalTitleFamily = await page.$eval('#id_Toc70759518', e=>getComputedStyle(e).fontFamily);
 const manifest=JSON.parse(fs.readFileSync(path.join(root,'assets/reader_fonts/manifest.json')));
 const counts=[];
 for (const font of manifest.fonts) {
   await page.evaluate(()=>window.readerGoPage(8));
   const saved=await page.evaluate(()=>window.calls.filter(c=>c[0]==='reader').at(-1)[1].offset);
   const family='ReaderFont_'+font.id;
   const faces=font.faces.map(face=>`@font-face{font-family:"${family}";src:url(data:font/woff2;base64,${fs.readFileSync(path.join(root,face.asset)).toString('base64')}) format("woff2");font-weight:${face.weight};font-style:${face.style};font-display:block;}`).join('');
   await page.evaluate(({faces,id,family})=>window.readerSetFont(faces,id,family),{faces,id:font.id,family});
   const status=await page.evaluate(({family,saved})=>{
     const main=document.querySelector('#book'), viewport=document.querySelector('#viewport');
     const title=getComputedStyle(document.querySelector('#id_Toc70759518'));
     const paragraph=getComputedStyle(document.querySelector('#family-probe'));
     let total=0,rect=null;
     const walker=document.createTreeWalker(main,NodeFilter.SHOW_TEXT);
     while(walker.nextNode()){
       const node=walker.currentNode;if(node.parentElement.closest('style,script'))continue;
       if(total+node.length>saved){const range=document.createRange();range.setStart(node,saved-total);range.setEnd(node,saved-total+1);rect=range.getBoundingClientRect();break;}total+=node.length;
     }
     const bounds=viewport.getBoundingClientRect();
     return {loaded:document.fonts.check(`20px "${family}"`),family:paragraph.fontFamily,
       weight:title.fontWeight,titleSize:parseFloat(title.fontSize),size:parseFloat(paragraph.fontSize),
       italic:getComputedStyle(document.querySelector('#emphasis-probe')).fontStyle,
       code:getComputedStyle(document.querySelector('#code-probe')).fontFamily,
       visible:rect&&rect.left>=bounds.left-1&&rect.left<bounds.right,
       live:window.calls.filter(c=>c[0]==='reader').at(-1)[1]};
   },{family,saved});
   assert(status.loaded, font.id+' did not load');
   assert(status.family.includes(family),font.id+' failed to override inline publisher font');
   assert(Number(status.weight)>=600&&status.titleSize>status.size*1.35,font.id+' lost heading emphasis');
   assert.equal(status.italic,'italic');assert(status.code.includes('monospace'));
   assert(status.visible,font.id+' lost reading passage');
   assert(status.live.layout.endsWith(':'+font.id));
   const measured=await page.evaluate(body=>window.readerMeasure(body),body);
   assert(measured.valid&&measured.count===status.live.count,font.id+' incorrect page count');
   counts.push(status.live.count);
   console.log('PASS '+font.label+': loaded offline, preserved passage/headings, '+status.live.count+' pages');
 }
 assert(new Set(counts).size>1,'font metrics did not change page counts');
 await page.evaluate(()=>window.readerSettings(28,false));
 await page.evaluate(()=>new Promise(requestAnimationFrame));
 const enlarged=await page.evaluate(body=>window.readerMeasure(body),body);
 const enlargedLive=await page.evaluate(()=>window.calls.filter(c=>c[0]==='reader').at(-1)[1]);
 assert.equal(enlarged.count,enlargedLive.count);
 assert(enlargedLive.layout.includes(':28px:opendyslexic'));
 console.log('PASS selected OpenDyslexic remains compatible with the text-size slider');
 await page.evaluate(()=>window.readerSetFont('','default',''));
 assert.equal(await page.$eval('#family-probe',e=>getComputedStyle(e).fontFamily),'monospace');
 assert.equal(await page.$eval('#id_Toc70759518',e=>getComputedStyle(e).fontFamily),originalTitleFamily);
 await page.evaluate(()=>window.readerSettings(28,false));
 await page.evaluate(()=>new Promise(requestAnimationFrame));
 const measured=await page.evaluate(body=>window.readerMeasure(body),body);
 const live=await page.evaluate(()=>window.calls.filter(c=>c[0]==='reader').at(-1)[1]);
 assert.equal(measured.count,live.count);
 assert.deepEqual(errors,[]);
 console.log('PASS book-default reset restores publisher families; font size/navigation remain compatible');
 } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
