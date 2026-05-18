with System;
with System.Machine_Code;
with Ada.Unchecked_Conversion;
procedure kernel_main (Magic : Integer; Multiboot_Info : Integer) is
   type Unsigned_32 is mod 2**32;
   function To_Address is new Ada.Unchecked_Conversion (Unsigned_32, System.Address);
   procedure Putln (S : String);
   procedure Cat_File (FName : String);
   type Word is mod 2**16;
   type Unsigned_8  is mod 2**8;
   type Unsigned_16 is mod 2**16;
   type File_Record is record
      Name    : String(1..64);
      Size    : Unsigned_32;
      Start_LBA : Unsigned_32;
   end record;
   Screen_Width  : constant := 80;
   Screen_Height : constant := 25;
   Video : array (0 .. Screen_Width * Screen_Height - 1) of Word;
   for Video'Address use System'To_Address (16#B8000#);
   pragma Import (Ada, Video);
   Cursor : Integer := 0;
   Max_Files : constant := 65536;
   Superblock_LBA : constant := 0;
   FileTable_Start : constant Unsigned_32 := 1;
   FileTable_End   : constant Unsigned_32 := FileTable_Start + Max_Files - 1;
   Data_Start_LBA  : constant Unsigned_32 := FileTable_End + 1;
   Next_Free_File : Integer := 1;
   ----------------------------------------------------------
   procedure Busy_Wait (Milliseconds : Positive) is
      Count : constant Integer := Integer(Milliseconds) * 250_000;
   begin
      for I in 1 .. Count loop
         null;
      end loop;
   end Busy_Wait;
   procedure New_Line is
      Current_Row : constant Integer := Cursor / Screen_Width;
   begin
      if Current_Row = Screen_Height - 1 then
         for Row in 1 .. Screen_Height - 1 loop
            for Col in 0 .. Screen_Width - 1 loop
               Video((Row - 1) * Screen_Width + Col) := Video(Row * Screen_Width + Col);
            end loop;
         end loop;
         for Col in 0 .. Screen_Width - 1 loop
            Video((Screen_Height - 1) * Screen_Width + Col) := 16#0F20#;
         end loop;
      else
         Cursor := (Current_Row + 1) * Screen_Width;
      end if;
   end New_Line;
   procedure Carriage_Return is
   begin
      Cursor := (Cursor / Screen_Width) * Screen_Width;
   end Carriage_Return;

   procedure PutChar (C : Character) is
   begin
      if C = Character'Val(10) then
         New_Line;
      elsif C = Character'Val(13) then
         Carriage_Return;
      else
         Video(Cursor) := Word(Character'Pos(C)) + 16#0F00#;
         Cursor := Cursor + 1;
         if Cursor >= Video'Length then
            Cursor := 0;
         end if;
      end if;
   end PutChar;

   procedure PutString (S : String) is
   begin
      for I in S'Range loop
         PutChar (S(I));
      end loop;
   end PutString;

   procedure ClearScreen is
   begin
      for I in Video'Range loop
         Video(I) := 16#0F20#;
      end loop;
      Cursor := 0;
   end ClearScreen;

   function Equal (S1, S2 : String) return Boolean is
   Len1 : Integer := 0;
   Len2 : Integer := 0;
begin
   for I in reverse S1'Range loop
      if S1(I) /= ' ' then
         Len1 := I - S1'First + 1;
         exit;
      end if;
   end loop;
   for I in reverse S2'Range loop
      if S2(I) /= ' ' then
         Len2 := I - S2'First + 1;
         exit;
      end if;
   end loop;

   if Len1 /= Len2 then
      return False;
   end if;

   for I in 1 .. Len1 loop
      if S1(S1'First + I - 1) /= S2(S2'First + I - 1) then
         return False;
      end if;
   end loop;

   return True;
   end Equal;
   function Get_Memory_Size (Multiboot_Info : Unsigned_32) return Unsigned_32 is
   type Multiboot_Info_Record is record
      Flags      : Unsigned_32;
      Mem_Lower  : Unsigned_32;
      Mem_Upper  : Unsigned_32;
   end record;
   Info : Multiboot_Info_Record;
   for Info'Address use To_Address(Multiboot_Info);
   pragma Import (Ada, Info);
begin
   if (Info.Flags and 1) = 1 then
      return (Info.Mem_Lower + Info.Mem_Upper) * 1024;
   else
      return 0;
   end if;
end Get_Memory_Size;
   ------------------------------------------------------
   type Token_Array is array (1 .. 10) of String(1..32);
Tokens : Token_Array;
Count  : Integer := 0;

procedure ParseCmd (Input : String) is
   In_Quote : Boolean := False;
   Token_Idx : Integer := 0;
   Pos : Integer := 0;
   Current_Token : String(1..32) := (others => ' ');
begin
   Count := 0;
   for I in Input'Range loop
      declare
         Ch : constant Character := Input(I);
      begin
         if Ch = '"' then
            In_Quote := not In_Quote;   --
         elsif (not In_Quote) and then Ch = ' ' then

            if Pos > 0 then
               Token_Idx := Token_Idx + 1;
               Current_Token(Pos+1..32) := (others => ' ');
               Tokens(Token_Idx) := Current_Token;
               Pos := 0;
               Current_Token := (others => ' ');
            end if;
         else

            if Pos < 32 then
               Pos := Pos + 1;
               Current_Token(Pos) := Ch;
            end if;
         end if;
      end;
   end loop;
   if Pos > 0 then
      Token_Idx := Token_Idx + 1;
      Current_Token(Pos+1..32) := (others => ' ');
      Tokens(Token_Idx) := Current_Token;
   end if;
   Count := Token_Idx;
end ParseCmd;
   ------------------------------------------------------
Shift_Pressed : Boolean := False;
subtype Scan_Code is Integer range 0 .. 16#58#;
type Key_Map is array (Scan_Code) of Character;
No_Key : constant Character := Character'Val(0);
Default_Map : Key_Map := (others => No_Key);
Shift_Map   : Key_Map := (others => No_Key);
procedure Init_Key_Maps is
begin
   Default_Map(16#1E#) := 'a';  Shift_Map(16#1E#) := 'A';
   Default_Map(16#30#) := 'b';  Shift_Map(16#30#) := 'B';
   Default_Map(16#2E#) := 'c';  Shift_Map(16#2E#) := 'C';
   Default_Map(16#20#) := 'd';  Shift_Map(16#20#) := 'D';
   Default_Map(16#12#) := 'e';  Shift_Map(16#12#) := 'E';
   Default_Map(16#21#) := 'f';  Shift_Map(16#21#) := 'F';
   Default_Map(16#22#) := 'g';  Shift_Map(16#22#) := 'G';
   Default_Map(16#23#) := 'h';  Shift_Map(16#23#) := 'H';
   Default_Map(16#17#) := 'i';  Shift_Map(16#17#) := 'I';
   Default_Map(16#24#) := 'j';  Shift_Map(16#24#) := 'J';
   Default_Map(16#25#) := 'k';  Shift_Map(16#25#) := 'K';
   Default_Map(16#26#) := 'l';  Shift_Map(16#26#) := 'L';
   Default_Map(16#32#) := 'm';  Shift_Map(16#32#) := 'M';
   Default_Map(16#31#) := 'n';  Shift_Map(16#31#) := 'N';
   Default_Map(16#18#) := 'o';  Shift_Map(16#18#) := 'O';
   Default_Map(16#19#) := 'p';  Shift_Map(16#19#) := 'P';
   Default_Map(16#10#) := 'q';  Shift_Map(16#10#) := 'Q';
   Default_Map(16#13#) := 'r';  Shift_Map(16#13#) := 'R';
   Default_Map(16#1F#) := 's';  Shift_Map(16#1F#) := 'S';
   Default_Map(16#14#) := 't';  Shift_Map(16#14#) := 'T';
   Default_Map(16#16#) := 'u';  Shift_Map(16#16#) := 'U';
   Default_Map(16#2F#) := 'v';  Shift_Map(16#2F#) := 'V';
   Default_Map(16#11#) := 'w';  Shift_Map(16#11#) := 'W';
   Default_Map(16#2D#) := 'x';  Shift_Map(16#2D#) := 'X';
   Default_Map(16#15#) := 'y';  Shift_Map(16#15#) := 'Y';
   Default_Map(16#2C#) := 'z';  Shift_Map(16#2C#) := 'Z';
   Default_Map(16#0B#) := '0';  Shift_Map(16#0B#) := ')';
   Default_Map(16#02#) := '1';  Shift_Map(16#02#) := '!';
   Default_Map(16#03#) := '2';  Shift_Map(16#03#) := '@';
   Default_Map(16#04#) := '3';  Shift_Map(16#04#) := '#';
   Default_Map(16#05#) := '4';  Shift_Map(16#05#) := '$';
   Default_Map(16#06#) := '5';  Shift_Map(16#06#) := '%';
   Default_Map(16#07#) := '6';  Shift_Map(16#07#) := '^';
   Default_Map(16#08#) := '7';  Shift_Map(16#08#) := '&';
   Default_Map(16#09#) := '8';  Shift_Map(16#09#) := '*';
   Default_Map(16#0A#) := '9';  Shift_Map(16#0A#) := '(';
   Default_Map(16#39#) := ' ';  Shift_Map(16#39#) := ' ';
   Default_Map(16#1C#) := Character'Val(13);
   Shift_Map(16#1C#)     := Character'Val(13);
   Default_Map(16#0E#) := Character'Val(8);
   Shift_Map(16#0E#)     := Character'Val(8);
   Default_Map(16#33#) := ',';  Shift_Map(16#33#) := '<';
   Default_Map(16#34#) := '.';  Shift_Map(16#34#) := '>';
   Default_Map(16#35#) := '/';  Shift_Map(16#35#) := '?';
   Default_Map(16#27#) := ';';  Shift_Map(16#27#) := ':';
   Default_Map(16#28#) := '''; Shift_Map(16#28#) := '"';
   Default_Map(16#2B#) := '\';  Shift_Map(16#2B#) := '|';
   Default_Map(16#1A#) := '[';  Shift_Map(16#1A#) := '{';
   Default_Map(16#1B#) := ']';  Shift_Map(16#1B#) := '}';
   Default_Map(16#0C#) := '-';  Shift_Map(16#0C#) := '_';
   Default_Map(16#0D#) := '=';  Shift_Map(16#0D#) := '+';
   Default_Map(16#29#) := '`';  Shift_Map(16#29#) := '~';
   end Init_Key_Maps;
   --==========================================--
   function Port_In (Port : Unsigned_16) return Unsigned_8 is
   Result : Unsigned_8;
   begin
      System.Machine_Code.Asm(
                              "inb %1, %0",
                              Outputs  => Unsigned_8'Asm_Output ("=a", Result),
                              Inputs   => Unsigned_16'Asm_Input ("d", Port),
                              Volatile => True
                             );
      return Result;
   end Port_In;
   procedure Port_Out (Port : Unsigned_16; Value : Unsigned_8) is
begin
   System.Machine_Code.Asm(
      "outb %0, %1",
      Inputs  => (Unsigned_8'Asm_Input ("a", Value),
                  Unsigned_16'Asm_Input ("d", Port)),
      Volatile => True);
   end Port_Out;
   function Shift_Right (Value : Unsigned_32; Amount : Natural) return Unsigned_32 is
begin
   return Value / (2**Amount);
   end Shift_Right;
   procedure Port_Out_Word (Port : Unsigned_16; Value : Unsigned_16) is
begin
   System.Machine_Code.Asm(
      "outw %0, %1",
      Inputs  => (Unsigned_16'Asm_Input ("a", Value),
                  Unsigned_16'Asm_Input ("d", Port)),
      Volatile => True);
end Port_Out_Word;
   ---===========================================--
   function Port_In_Word (Port : Unsigned_16) return Unsigned_16 is
   Result : Unsigned_16;
begin
   System.Machine_Code.Asm(
      "inw %1, %0",
      Outputs  => Unsigned_16'Asm_Output ("=a", Result),
      Inputs   => Unsigned_16'Asm_Input  ("d", Port),
      Volatile => True);
   return Result;
end Port_In_Word;
   type Sector_Data is array (0 .. 511) of Unsigned_8;
type Sector_Words is array (0 .. 255) of Unsigned_16;
type Sector_Buffer (As_Words : Boolean := False) is record
   case As_Words is
      when True  => Words : Sector_Words;
      when False => Bytes : Sector_Data;
   end case;
end record;
procedure Read_Sector (LBA : Unsigned_32; Buffer : out Sector_Buffer) is
   use type Unsigned_8;
   Status : Unsigned_8;
   LBA_Lo   : constant Unsigned_8 := Unsigned_8(LBA and 16#FF#);
   LBA_Mid  : constant Unsigned_8 := Unsigned_8(Shift_Right(LBA, 8) and 16#FF#);
   LBA_Hi   : constant Unsigned_8 := Unsigned_8(Shift_Right(LBA, 16) and 16#FF#);
begin
   Port_Out(16#1F6#, 16#E0# or (Unsigned_8(Shift_Right(LBA, 24) and 16#0F#)));
   Port_Out(16#1F2#, 1);
   Port_Out(16#1F3#, LBA_Lo);
   Port_Out(16#1F4#, LBA_Mid);
   Port_Out(16#1F5#, LBA_Hi);
   Port_Out(16#1F7#, 16#20#);
   loop
         Status := Port_In(16#1F7#);
         exit when (Status and 16#80#) = 0;
   end loop;
   if (Status and 8) = 0 then
      return;
   end if;
   for I in 0 .. 255 loop
      Buffer.Words(I) := Port_In_Word(16#1F0#);
   end loop;
   end Read_Sector;
   procedure Write_Sector (LBA : Unsigned_32; Buffer : in Sector_Buffer) is
   use type Unsigned_8;
   Status : Unsigned_8;
   LBA_Lo   : constant Unsigned_8 := Unsigned_8(LBA and 16#FF#);
   LBA_Mid  : constant Unsigned_8 := Unsigned_8(Shift_Right(LBA, 8) and 16#FF#);
   LBA_Hi   : constant Unsigned_8 := Unsigned_8(Shift_Right(LBA, 16) and 16#FF#);
begin
   Port_Out(16#1F6#, 16#E0# or (Unsigned_8(Shift_Right(LBA, 24) and 16#0F#)));
   Port_Out(16#1F2#, 1);
   Port_Out(16#1F3#, LBA_Lo);
   Port_Out(16#1F4#, LBA_Mid);
   Port_Out(16#1F5#, LBA_Hi);
   Port_Out(16#1F7#, 16#30#);

   loop
      Status := Port_In(16#1F7#);
      exit when (Status and 16#80#) = 0;
   end loop;

   for I in 0 .. 255 loop
      Port_Out_Word(16#1F0#, Buffer.Words(I));
   end loop;
   end Write_Sector;
   --================================---
   procedure Format_Disk is
   Buf : Sector_Buffer(As_Words => False);
begin
   Buf.Bytes := (others => 0);
   Buf.Bytes(0) := 16#53#; -- 'S'
   Buf.Bytes(1) := 16#49#;
   Buf.Bytes(2) := 16#4E#;
   Buf.Bytes(3) := 16#45#;
   Write_Sector(Superblock_LBA, Buf);
   Buf.Bytes := (others => 0);
   for LBA in FileTable_Start .. FileTable_End loop
      Write_Sector(LBA, Buf);
   end loop;

   Putln("Disk formatted. Max files: 65536");
   end Format_Disk;
   function Count_Files return Unsigned_32 is
   Buf : Sector_Buffer(As_Words => False);
   Count : Unsigned_32 := 0;
begin
   for LBA in FileTable_Start .. FileTable_End loop
      Read_Sector(LBA, Buf);
      if Buf.Bytes(0) /= 0 and then Buf.Bytes(0) /= 16#20# then
         Count := Count + 1;
      end if;
   end loop;
   return Count;
   end Count_Files;
      function Find_Free_Entry return Unsigned_32;
   procedure Create_File (FName : String) is
   LBA : Unsigned_32;
   Buf : Sector_Buffer(As_Words => False);
begin
   LBA := Find_Free_Entry;
   if LBA = 0 then
      Putln("File table full.");
      return;
   end if;
   for I in 1..FName'Length loop
      Buf.Bytes(I-1) := Character'Pos(FName(I));
   end loop;
   Buf.Bytes(64..67) := (others => 0);
   declare
      File_Index : Unsigned_32 := LBA - FileTable_Start;
      Start : constant Unsigned_32 := Data_Start_LBA + File_Index * 10;
   begin
      Buf.Bytes(68) := Unsigned_8(Start and 16#FF#);
      Buf.Bytes(69) := Unsigned_8(Shift_Right(Start, 8) and 16#FF#);
      Buf.Bytes(70) := Unsigned_8(Shift_Right(Start, 16) and 16#FF#);
      Buf.Bytes(71) := Unsigned_8(Shift_Right(Start, 24) and 16#FF#);
   end;
   Write_Sector(LBA, Buf);
   PutString("File created: ");
      Putln(FName);
end Create_File;
   procedure List_Files is
   Buf : Sector_Buffer(As_Words => False);
   Name : String(1..64);
   Found : Boolean := False;
begin
   for I in 1..Max_Files loop
      Read_Sector(FileTable_Start + Unsigned_32(I - 1), Buf);
      for J in 1..64 loop
         Name(J) := Character'Val(Buf.Bytes(J-1));
      end loop;
      if Name(1) /= Character'Val(0) and then Name(1) /= ' ' then
         PutString(Name);
         New_Line;
         Found := True;
      end if;
   end loop;
   if not Found then
      Putln("No files.");
   end if;
   end List_Files;
   procedure Cat_File (FName : String) is
   Buf : Sector_Buffer(As_Words => False);
   Name : String(1..64);
   File_Size : Unsigned_32;
   Start_LBA : Unsigned_32;
   Found : Boolean := False;
   Data_Buf : Sector_Buffer(As_Words => False);
begin
   for I in 1..Max_Files loop
      Read_Sector(FileTable_Start + Unsigned_32(I - 1), Buf);
      for J in 1..64 loop
         Name(J) := Character'Val(Buf.Bytes(J-1));
      end loop;
      if Equal(Name, FName) then
         Found := True;
         File_Size := Unsigned_32(Buf.Bytes(64)) or
                      (Unsigned_32(Buf.Bytes(65)) * 2**8) or
                      (Unsigned_32(Buf.Bytes(66)) * 2**16) or
                      (Unsigned_32(Buf.Bytes(67)) * 2**24);
         Start_LBA := Unsigned_32(Buf.Bytes(68)) or
                      (Unsigned_32(Buf.Bytes(69)) * 2**8) or
                      (Unsigned_32(Buf.Bytes(70)) * 2**16) or
                      (Unsigned_32(Buf.Bytes(71)) * 2**24);
         exit;
      end if;
   end loop;
   if not Found then
      Putln("File not found.");
      return;
   end if;


   declare
      Sectors : constant Integer := Integer(File_Size + 511) / 512;
   begin
      for Sec in 0 .. Sectors - 1 loop
         Read_Sector(Start_LBA + Unsigned_32(Sec), Data_Buf);

         for Byte_Idx in 0 .. 511 loop
            declare
               Global_Idx : constant Unsigned_32 := Unsigned_32(Sec) * 512 + Unsigned_32(Byte_Idx);
            begin
               exit when Global_Idx >= File_Size;
               PutChar(Character'Val(Data_Buf.Bytes(Byte_Idx)));
            end;
         end loop;
      end loop;
   end;
   New_Line;
   end Cat_File;
   function Find_Free_Entry return Unsigned_32 is
   Buf : Sector_Buffer(As_Words => False);
begin
   for LBA in FileTable_Start .. FileTable_End loop
      Read_Sector(LBA, Buf);
      if Buf.Bytes(0) = 0 or else Buf.Bytes(0) = 16#20# then
         return LBA;
      end if;
   end loop;
   return 0;
   end Find_Free_Entry;
   function Find_File_LBA (FName : String) return Unsigned_32 is
   Buf : Sector_Buffer(As_Words => False);
   Name : String(1..64);
begin
   for LBA in FileTable_Start .. FileTable_End loop
      Read_Sector(LBA, Buf);
      if Buf.Bytes(0) = 0 or else Buf.Bytes(0) = 16#20# then
         goto Continue;
      end if;
      for J in 1..64 loop
         Name(J) := Character'Val(Buf.Bytes(J-1));
      end loop;
      if Equal(Name, FName) then
         return LBA;
      end if;
      <<Continue>>
   end loop;
   return 0;
   end Find_File_LBA;
   procedure Write_File (FName : String; Data : String) is
   LBA : Unsigned_32;
   Buf : Sector_Buffer(As_Words => False);
   File_Size : Unsigned_32;
   Start_LBA : Unsigned_32;
begin
   LBA := Find_File_LBA(FName);
   if LBA = 0 then
      Putln("File not found.");
      return;
   end if;
   Read_Sector(LBA, Buf);
   File_Size := Unsigned_32(Buf.Bytes(64)) or
                (Unsigned_32(Buf.Bytes(65)) * 2**8) or
                (Unsigned_32(Buf.Bytes(66)) * 2**16) or
                (Unsigned_32(Buf.Bytes(67)) * 2**24);
   Start_LBA := Unsigned_32(Buf.Bytes(68)) or
                (Unsigned_32(Buf.Bytes(69)) * 2**8) or
                (Unsigned_32(Buf.Bytes(70)) * 2**16) or
                (Unsigned_32(Buf.Bytes(71)) * 2**24);
   if Data'Length > 10 * 512 then
      Putln("Data too large (max 5KB).");
      return;
   end if;

   declare
      Data_Idx : Integer := Data'First;
      Ch : Unsigned_8;
   begin
      for Sec in 0 .. 9 loop
         Buf.Bytes := (others => 0);
         for Byte_Idx in 0 .. 511 loop
            exit when Data_Idx > Data'Last;
            Buf.Bytes(Byte_Idx) := Character'Pos(Data(Data_Idx));
            Data_Idx := Data_Idx + 1;
         end loop;
         Write_Sector(Start_LBA + Unsigned_32(Sec), Buf);
         if Data_Idx > Data'Last then
            exit;
         end if;
      end loop;
   end;
   File_Size := Unsigned_32(Data'Length);
   Buf.Bytes(64) := Unsigned_8(File_Size and 16#FF#);
   Buf.Bytes(65) := Unsigned_8(Shift_Right(File_Size, 8) and 16#FF#);
   Buf.Bytes(66) := Unsigned_8(Shift_Right(File_Size, 16) and 16#FF#);
   Buf.Bytes(67) := Unsigned_8(Shift_Right(File_Size, 24) and 16#FF#);
   Write_Sector(LBA, Buf);

   Putln("Written.");
end Write_File;
   --==========================================--
function Read_Key return Character is
   Status  : Unsigned_8;
   Scancode : Unsigned_8;
   Ch      : Character;
   use type Unsigned_8;
begin
   loop
      loop
         Status := Port_In(16#64#);
         exit when (Status and 1) = 1;
      end loop;
      Scancode := Port_In(16#60#);
      if Scancode = 16#2A# then
         Shift_Pressed := True;
      elsif Scancode = 16#AA# then
         Shift_Pressed := False;
      elsif Scancode < 16#80# then
        if Shift_Pressed then
            Ch := Shift_Map(Scan_Code(Scancode));
        else
            Ch := Default_Map(Scan_Code(Scancode));
        end if;
        if Ch /= No_Key then
            return Ch;
        end if;
     end if;
   end loop;
   end Read_Key;
   --=======================================--
procedure Read_Line (Buffer : out String; Length : out Integer) is
   Ch : Character;
   Pos : Integer := 0;
begin
   loop
      Ch := Read_Key;
      if Ch = Character'Val(13) then   --
         New_Line;
         exit;
      elsif Ch = Character'Val(8) then --
         if Pos > 0 then
            Pos := Pos - 1;
            Carriage_Return;
            PutChar(' ');
            Carriage_Return;
         end if;
      else
         if Pos < Buffer'Length - 1 then
            Pos := Pos + 1;
            Buffer(Pos) := Ch;
            PutChar(Ch);  --
         end if;
      end if;
   end loop;
   Buffer(Pos + 1) := Character'Val(0);  --
   Length := Pos;
end Read_Line;
   ---------------------------------------------
   procedure Putln(s:String)is
   begin
      PutString(s);
      New_Line;
   end Putln;
   procedure Put_Number (N : Unsigned_32) is
      Divisor : Unsigned_32 := 1000000000;
      Started : Boolean := False;
   begin
      if N = 0 then PutChar('0'); return; end if;
      while Divisor > 0 loop
         declare
            Digit : constant Unsigned_32 := N / Divisor mod 10;
         begin
            if Digit /= 0 or Started or Divisor = 1 then
               PutChar(Character'Val(48 + Digit));
               Started := True;
            end if;
            Divisor := Divisor / 10;
         end;
      end loop;
   end Put_Number;
   ---------------------------------------------
begin
   Init_Key_Maps;
   ClearScreen;
   PutString("================");
   Busy_Wait(2000);
   New_Line;
   Putln("SiNetDOS - Alpha 1");
   Putln("Welcome back!");
   PutString("Total memory: ");
   declare
      Buffer : String(1..80);
      Len : Integer;
      Mem : Unsigned_32 := Get_Memory_Size(Unsigned_32(Multiboot_Info));
   begin
      Put_Number(Mem);
      PutString(" bytes");
      New_Line;
      PutString("Files on disk: ");
      Put_Number(Count_Files);
      New_Line;
      loop
         New_Line;
         PutChar('>');
         Read_Line(Buffer, Len);
         ParseCmd(Buffer(1..Len));
         PutString(Buffer(1..Len));
         if Count > 0 then
            if Equal(Tokens(1), "cls") then
               ClearScreen;
            elsif Equal(Tokens(1), "echo") then
               for I in 2 .. Count loop
                  PutString(Tokens(I));
                  if I < Count then PutChar(' '); end if;
               end loop;
               New_Line;
            elsif Equal(Tokens(1), "diskinfo") then
               declare
                  Buf : Sector_Buffer(As_Words => False);
               begin
                  Read_Sector(0, Buf);
                  PutString("LBA 0 first 16 bytes: ");
                  New_Line;
                  for I in 0 .. 15 loop
                     PutChar(Character'Val(Buf.Bytes(I) mod 128));
                  end loop;
                  New_Line;
               end;
            elsif Equal(Tokens(1), "format") then
               Format_Disk;
            elsif Equal(Tokens(1), "mkfile") then
               if Count >= 2 then
                  Create_File(Tokens(2));
               end if;
            elsif Equal(Tokens(1), "ls") then
               List_Files;
            elsif Equal(Tokens(1), "cat") then
               if Count >= 2 then
                  Cat_File(Tokens(2));
               end if;
            elsif Equal(Tokens(1), "write") then
               if Count >= 3 then
                  Write_File(Tokens(2), Tokens(3));
               else
                  Putln("Usage: write <file> <text>");
               end if;
            elsif Equal(Tokens(1), "mem") then
               Put_Number(Get_Memory_Size(Unsigned_32(Multiboot_Info)));
               Putln(" bytes");
            else
               PutString("Unknown command: ");
               PutString(Tokens(1));
               New_Line;
            end if;
         end if;
      end loop;
      --loop null; end loop;
   end;
end kernel_main;
