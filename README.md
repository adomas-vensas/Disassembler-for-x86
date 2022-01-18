<h1>Disassembler</h1>
<h3>Introduction</h3>

VERSION: 1.0<br>
AUTHOR: Adomas Vensas<br>
CONTACTS: adomasve@gmail.com<br>

This is a disassembler for the Intel 8086/8088 processor. Newer processors are not supported, neither the instructions of the Intel 8087 coprocessor. The program was originally made on YASM and was not tested with other compilers.<br>

The program disassembles .COM file's instructions and returns their assembly language equivalents. If no corresponding instructions were found, the disassembler prints out 'DB xx' (xx - byte).<br>

A barebones template was provided by Computer Architecture professor Irus Grinis from Vilnius University. Template included a few one byte instructions, procedures to open and close file, procedure to read COM file's name without extension.

<strong>Note</strong>:
<ul>
  <li>Many disassembler instructions can be encoded in syntactically different but semantically analogue ways.</li>
  <li>This program is only used with .COM files. Therefore, all instructions must be written from the starting address 0x0100</li>
</ul>
<h3>Tools</h3>
Most of the tools needed to start the program are in the 'x86Disasm' folder:
<ul>
  <li>DOSBOX emulator: https://www.dosbox.com/download.php?main=1 (emulate 8086 processor's environment)</li>
  <li>YASM.exe and CWSDPMI.exe (to compile .COM file)</li>
  <li>DEBUG.com program (to access the processor and write instructions)</li>
  <li>DISASM.asm file (the disassembler's code file)</li>
</ul>

<h3> Start DEBUG </h3>

<strong>ON WINDOWS:</strong>
<ol>
    <li>Unzip the 'x86Disasm.zip'</li>
    <li>Open DOSBOX</li>
    <li>Write 'mount c ' and directory of the 'x86Disasm' folder</li>
    <li>After successful mount, type 'C:'</li>
    <li>Write 'debug' and press ENTER. You will start the debugger</li>
</ol>
<strong>ON LINUX:</strong>
<ol>
  <li>Unzip the 'x86Disasm.zip'</li>
  <li>Right-click the unzipped folder and run it in the console</li>
  <li>In the command-line write: '. dosbox'</li>
  <li>Afte successful mount, type DEBUG in DOSBOX and press ENTER. You will start the debugger</li>
</ol>
<strong>Note:</strong> Compiled instruction files must be written without '.COM' extension when starting them in disassembler.<br>
A short video on how to write instructions in DEBUG and make a .COM file: https://www.youtube.com/watch?v=ZNPPpSL8Teo<br>

<h3> Supported instructions </h3>
All instructions from the 'instr86.pdf' file.<br>
<strong>Note:</strong> File contains errors. However, it is a very comprehensive instruction file.<br>
<strong>Errors:</strong>
<ul>
  <li>BAS is not an instruction. Correction: DAS</li>
  <li>SSB is not an instruction. Correction: SBB</li>
  <li>'SBB Immediate to Accumulator' first byte is incorrect. Correction: 0001110w</li>
</ul>

Copyright (C) 2021 Adomas Vensas, Vilnius University
