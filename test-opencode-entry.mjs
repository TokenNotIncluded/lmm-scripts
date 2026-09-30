import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, copyFile, writeFile, readFile, rm, chmod} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {existsSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
test('Unix wrapper preserves literal arguments and propagates child failure', {skip:process.platform==='win32'}, async()=>{
 const work=await mkdtemp(join(tmpdir(),'lmm-wrapper-'));
 try{
  await copyFile(resolve('opencode.sh'),join(work,'opencode.sh'));
  const receipt=join(work,'receipt.json');
  await writeFile(join(work,'opencode.mjs'),'import fs from "node:fs";fs.writeFileSync(process.env.RECEIPT,JSON.stringify(process.argv.slice(2)));process.exit(17);');
  const args=['literal $(no-command); & |', '', 'quoted "data"'];
  const result=spawnSync('bash',[join(work,'opencode.sh'),...args],{env:{...process.env,RECEIPT:receipt}});
  assert.equal(result.status,17);
  assert.deepEqual(JSON.parse(await readFile(receipt,'utf8')),args);
 }finally{await rm(work,{recursive:true,force:true});}
});
test('Unix detached wrapper never executes a mismatched helper download', {skip:process.platform==='win32'},async()=>{
 const work=await mkdtemp(join(tmpdir(),'lmm-checksum-'));
 try{
  await copyFile(resolve('opencode.sh'),join(work,'opencode.sh'));
  const marker=join(work,'executed');
  await writeFile(join(work,'curl'),'#!/usr/bin/env node\nconst fs=require("node:fs");fs.writeFileSync(process.argv[process.argv.indexOf("-o")+1],`import fs from "node:fs";fs.writeFileSync(process.env.MARKER,"BAD");`);');
  await chmod(join(work,'curl'),0o755);
  const result=spawnSync('bash',[join(work,'opencode.sh')],{env:{...process.env,PATH:work+':'+process.env.PATH,MARKER:marker},encoding:'utf8'});
  assert.notEqual(result.status,0);
  assert.match(result.stderr,/checksum mismatch/);
  assert.equal(existsSync(marker),false);
 }finally{await rm(work,{recursive:true,force:true});}
});
