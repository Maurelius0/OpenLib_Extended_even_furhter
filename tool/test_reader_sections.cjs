const {chromium}=require('playwright');
const fs=require('fs'),path=require('path'),assert=require('assert');
const root=path.resolve(__dirname,'..');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.READER_CHROMIUM_PATH,headless:true,args:['--no-sandbox']});
 try {
 const page=await browser.newPage({viewport:{width:412,height:800}});
 const dart=fs.readFileSync(path.join(root,'lib/ui/epub_viewer.dart'),'utf8');
 const css=dart.split('<style>')[1].split('</style>')[0].replace('${_fontSize}',20);
 const script=fs.readFileSync(path.join(root,'lib/ui/components/epub_pagination.js'),'utf8');
 const body='<h1 id="one">Chapter one</h1>'+('<p>First chapter text with enough words for several pages.</p>'.repeat(80))+
  '<p id="two" style="font-size:1.4em;font-weight:bold">Chapter two</p>'+('<p>Second chapter text and credit cycles to read.</p>'.repeat(80))+
  '<p id="sub" style="font-weight:bold">The Fundamentals</p>'+('<p>Subsection words explaining money and credit.</p>'.repeat(50));
 async function load(body,labels) {
  await page.setContent(`<html><head><style>${css}</style></head><body><div id="viewport"><main id="book" class="reader-section">${body}</main></div></body></html>`);
  await page.evaluate(labels=>{window.readerSections=labels;window.readerFontFamily='';window.calls=[];window.flutter_inappwebview={callHandler:(...v)=>window.calls.push(v)}},labels);
  await page.addScriptTag({content:script});
  await page.evaluate(async()=>{await Promise.all(Array.from(document.images).map(i=>i.decode().catch(()=>{})));window.readerRestore(0,false)});
  await page.evaluate(()=>new Promise(requestAnimationFrame));
 }
 const current=()=>page.evaluate(()=>window.calls.filter(c=>c[0]==='reader').at(-1)[1]);
 await load(body,[{title:'Part One',anchor:null},{title:'Chapter one',anchor:'one'},
  {title:'Chapter two',anchor:'two'},{title:'The Fundamentals',anchor:'sub'},{title:'Missing',anchor:'absent'}]);
 assert.equal((await current()).partTitle,'Chapter one');
 for(const [id,title] of [['two','Chapter two'],['sub','The Fundamentals']]) {
  await page.evaluate(id=>window.readerAnchor(id),id);
  const before=await current();assert.equal(before.partTitle,title);
  await page.evaluate(p=>window.readerPreviewPage(p+1),before.page);
  const preview=await current();assert.equal(preview.partTitle,title);assert(preview.preview);
 }
 await page.evaluate(()=>window.readerGoPage(0));assert.equal((await current()).partTitle,'Chapter one');
 await page.evaluate(()=>{window.markerReads=0;for(const id of ['one','two','sub']){
   const target=document.getElementById(id),original=target.getBoundingClientRect.bind(target);
   target.getBoundingClientRect=()=>{window.markerReads++;return original()};}
   for(let p=0;p<8;p++)window.readerPreviewPage(p);
 });
 assert.equal(await page.evaluate(()=>window.markerReads),0,'page turns remeasure cached section markers');

 await page.evaluate(()=>window.readerSettings(28,false));
 await page.evaluate(()=>new Promise(requestAnimationFrame));
 await page.evaluate(()=>window.readerAnchor('two'));assert.equal((await current()).partTitle,'Chapter two');
 assert(await page.evaluate(()=>window.markerReads)>0,'font size did not refresh marker positions');
 await page.setViewportSize({width:780,height:412});await page.waitForTimeout(150);
 await page.evaluate(()=>window.readerAnchor('sub'));assert.equal((await current()).partTitle,'The Fundamentals');
 const font=JSON.parse(fs.readFileSync(path.join(root,'assets/reader_fonts/manifest.json'))).fonts[0];
 const family='ReaderFont_'+font.id;
 const faces=font.faces.map(f=>`@font-face{font-family:"${family}";src:url(data:font/woff2;base64,${fs.readFileSync(path.join(root,f.asset)).toString('base64')}) format("woff2");font-weight:${f.weight};font-style:${f.style};}`).join('');
 await page.evaluate(({faces,family})=>window.readerSetFont(faces,'literata',family),{faces,family});
 await page.evaluate(()=>window.readerAnchor('two'));assert.equal((await current()).partTitle,'Chapter two');
 console.log('PASS chapter/subsection labels follow taps, seeking, previews, font size, rotation and font family changes');
 await load('<p>Unlabelled opening text.</p>'.repeat(80)+'<h1 id="late">A later chapter</h1>',
   [{title:'A later chapter',anchor:'late'}]);
 assert.equal((await current()).partTitle,'');
 await page.evaluate(()=>window.readerAnchor('late'));
 assert.equal((await current()).partTitle,'A later chapter');
 console.log('PASS unlabelled opening pages do not borrow a future chapter title');
 const realBody=fs.readFileSync(process.env.READER_TEST_HTML,'utf8');
 const labels=JSON.parse(fs.readFileSync(process.env.READER_TEST_SECTIONS,'utf8'));
 await load(realBody,labels);
 const found=[];
 for(const id of ['id_Toc70759504','id_Toc70759514','id_Toc70759517','id_Toc70759518']) {
  await page.evaluate(id=>window.readerAnchor(id),id);
  const result=await current();assert(labels.some(l=>l.title===result.partTitle));found.push(result.partTitle);
  console.log('PASS real book current part: '+result.partTitle);
 }
 assert(new Set(found).size>=3);
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exit(1)});
