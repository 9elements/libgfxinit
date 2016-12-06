--
-- Copyright (C) 2015-2016 secunet Security Networks AG
--
-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation; either version 2 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--

with HW.Debug;
with GNAT.Source_Info;

with HW.GFX.GMA.Config;
with HW.GFX.GMA.DP_Info;
with HW.GFX.GMA.Registers;

use type HW.Word64;
use type HW.Pos16;
use type HW.GFX.GMA.Registers.Registers_Invalid_Index;

package body HW.GFX.GMA.Pipe_Setup is

   type Default_Head_Array is array (Pipe_Index) of Pipe_Head;
   Default_Pipe_Head : constant Default_Head_Array :=
     (Primary     => Head_A,
      Secondary   => Head_B,
      Tertiary    => Head_C);

   function Get_Pipe_Head (Pipe : Pipe_Index; Port : GPU_Port) return Pipe_Head
   is
   begin
      return
        (if Config.Has_EDP_Pipe and then Port = DIGI_A then
            Head_EDP
         else
            Default_Pipe_Head (Pipe));
   end Get_Pipe_Head;

   ----------------------------------------------------------------------------

   ILK_DISPLAY_CHICKEN1_VGA_MASK       : constant := 7 * 2 ** 29;
   ILK_DISPLAY_CHICKEN1_VGA_ENABLE     : constant := 5 * 2 ** 29;
   ILK_DISPLAY_CHICKEN2_VGA_MASK       : constant := 1 * 2 ** 25;
   ILK_DISPLAY_CHICKEN2_VGA_ENABLE     : constant := 0 * 2 ** 25;

   DSPCNTR_ENABLE               : constant :=  1 * 2 ** 31;
   DSPCNTR_GAMMA_CORRECTION     : constant :=  1 * 2 ** 30;
   DSPCNTR_DISABLE_TRICKLE_FEED : constant :=  1 * 2 ** 14;
   DSPCNTR_FORMAT_MASK          : constant := 15 * 2 ** 26;

   DSPCNTR_MASK : constant Word32 :=
      DSPCNTR_ENABLE or
      DSPCNTR_GAMMA_CORRECTION or
      DSPCNTR_FORMAT_MASK or
      DSPCNTR_DISABLE_TRICKLE_FEED;

   PLANE_CTL_PLANE_ENABLE              : constant := 1 * 2 ** 31;
   PLANE_CTL_SRC_PIX_FMT_RGB_32B_8888  : constant := 4 * 2 ** 24;
   PLANE_CTL_PLANE_GAMMA_DISABLE       : constant := 1 * 2 ** 13;

   PLANE_WM_ENABLE                     : constant :=        1 * 2 ** 31;
   PLANE_WM_LINES_SHIFT                : constant :=                 14;
   PLANE_WM_LINES_MASK                 : constant := 16#001f# * 2 ** 14;
   PLANE_WM_BLOCKS_MASK                : constant := 16#03ff# * 2 **  0;

   SPCNTR_ENABLE : constant :=  1 * 2 ** 31;

   VGA_SR_INDEX                        : constant :=   16#03c4#;
   VGA_SR_DATA                         : constant :=   16#03c5#;
   VGA_SR01                            : constant :=     16#01#;
   VGA_SR01_SCREEN_OFF                 : constant := 1 * 2 ** 5;

   VGA_CONTROL_VGA_DISPLAY_DISABLE     : constant :=        1 * 2 ** 31;
   VGA_CONTROL_BLINK_DUTY_CYCLE_MASK   : constant := 16#0003# * 2 **  6;
   VGA_CONTROL_BLINK_DUTY_CYCLE_50     : constant :=        2 * 2 **  6;
   VGA_CONTROL_VSYNC_BLINK_RATE_MASK   : constant := 16#003f# * 2 **  0;

   subtype VGA_Cycle_Count is Pos32 range 2 .. 128;
   function VGA_CONTROL_VSYNC_BLINK_RATE
     (Cycles : VGA_Cycle_Count)
      return Word32
   is
   begin
      return Word32 (Cycles) / 2 - 1;
   end VGA_CONTROL_VSYNC_BLINK_RATE;

   TRANS_CLK_SEL_PORT_NONE : constant := 0 * 2 ** 29;

   type TRANS_CLK_SEL_PORT_Array is
      array (Digital_Port) of Word32;
   TRANS_CLK_SEL_PORT : constant TRANS_CLK_SEL_PORT_Array :=
      TRANS_CLK_SEL_PORT_Array'
     (DIGI_A => 0 * 2 ** 29,   -- DDI A is not selectable
      DIGI_B => 2 * 2 ** 29,
      DIGI_C => 3 * 2 ** 29,
      DIGI_D => 4 * 2 ** 29,
      DIGI_E => 5 * 2 ** 29);

   PIPECONF_ENABLE          : constant := 1 * 2 ** 31;
   PIPECONF_ENABLED_STATUS  : constant := 1 * 2 ** 30;
   PIPECONF_ENABLE_DITHER   : constant := 1 * 2 **  4;
   PIPECONF_DITHER_TEMPORAL : constant := 1 * 2 **  2;

   function PIPECONF_BPC (Bits_Per_Color : BPC_Type) return Word32
   with
      Pre => True
   is
   begin
      return
        (case Bits_Per_Color is
            when      6 => 2 * 2 ** 5,
            when     10 => 1 * 2 ** 5,
            when     12 => 3 * 2 ** 5,
            when others => 0 * 2 ** 5);
   end PIPECONF_BPC;

   function PIPECONF_Misc (BPC : BPC_Type; Dither : Boolean) return Word32
   with
      Pre => True
   is
   begin
      return
        (if Config.Has_Pipeconf_BPC then PIPECONF_BPC (BPC) else 0) or
        (if Dither then PIPECONF_ENABLE_DITHER else 0);
   end PIPECONF_Misc;

   PF_CTRL_ENABLE                         : constant := 1 * 2 ** 31;
   PF_CTRL_PIPE_SELECT_MASK               : constant := 3 * 2 ** 29;
   PF_CTRL_FILTER_MED                     : constant := 1 * 2 ** 23;

   PS_CTRL_ENABLE_SCALER                  : constant := 1 * 2 ** 31;
   PS_CTRL_SCALER_MODE_7X5_EXTENDED       : constant := 1 * 2 ** 28;
   PS_CTRL_FILTER_SELECT_MEDIUM_2         : constant := 1 * 2 ** 23;

   PIPE_DDI_FUNC_CTL_ENABLE               : constant := 1 * 2 ** 31;
   PIPE_DDI_FUNC_CTL_DDI_SELECT_MASK      : constant := 7 * 2 ** 28;
   PIPE_DDI_FUNC_CTL_DDI_SELECT_NONE      : constant := 0 * 2 ** 28;
   PIPE_DDI_FUNC_CTL_DDI_SELECT_B         : constant := 1 * 2 ** 28;
   PIPE_DDI_FUNC_CTL_DDI_SELECT_C         : constant := 2 * 2 ** 28;
   PIPE_DDI_FUNC_CTL_DDI_SELECT_D         : constant := 3 * 2 ** 28;
   PIPE_DDI_FUNC_CTL_DDI_SELECT_E         : constant := 4 * 2 ** 28;
   PIPE_DDI_FUNC_CTL_MODE_SELECT_MASK     : constant := 7 * 2 ** 24;
   PIPE_DDI_FUNC_CTL_MODE_SELECT_HDMI     : constant := 0 * 2 ** 24;
   PIPE_DDI_FUNC_CTL_MODE_SELECT_DVI      : constant := 1 * 2 ** 24;
   PIPE_DDI_FUNC_CTL_MODE_SELECT_DP_SST   : constant := 2 * 2 ** 24;
   PIPE_DDI_FUNC_CTL_MODE_SELECT_DP_MST   : constant := 3 * 2 ** 24;
   PIPE_DDI_FUNC_CTL_MODE_SELECT_FDI      : constant := 4 * 2 ** 24;
   PIPE_DDI_FUNC_CTL_BPC_MASK             : constant := 7 * 2 ** 20;
   PIPE_DDI_FUNC_CTL_BPC_8BITS            : constant := 0 * 2 ** 20;
   PIPE_DDI_FUNC_CTL_BPC_10BITS           : constant := 1 * 2 ** 20;
   PIPE_DDI_FUNC_CTL_BPC_6BITS            : constant := 2 * 2 ** 20;
   PIPE_DDI_FUNC_CTL_BPC_12BITS           : constant := 3 * 2 ** 20;
   PIPE_DDI_FUNC_CTL_VSYNC_ACTIVE_LOW     : constant := 0 * 2 ** 17;
   PIPE_DDI_FUNC_CTL_VSYNC_ACTIVE_HIGH    : constant := 1 * 2 ** 17;
   PIPE_DDI_FUNC_CTL_HSYNC_ACTIVE_LOW     : constant := 0 * 2 ** 16;
   PIPE_DDI_FUNC_CTL_HSYNC_ACTIVE_HIGH    : constant := 1 * 2 ** 16;
   PIPE_DDI_FUNC_CTL_EDP_SELECT_MASK      : constant := 7 * 2 ** 12;
   PIPE_DDI_FUNC_CTL_EDP_SELECT_ALWAYS_ON : constant := 0 * 2 ** 12;
   PIPE_DDI_FUNC_CTL_EDP_SELECT_A         : constant := 4 * 2 ** 12;
   PIPE_DDI_FUNC_CTL_EDP_SELECT_B         : constant := 5 * 2 ** 12;
   PIPE_DDI_FUNC_CTL_EDP_SELECT_C         : constant := 6 * 2 ** 12;
   PIPE_DDI_FUNC_CTL_DP_VC_PAYLOAD_ALLOC  : constant := 1 * 2 **  8;
   PIPE_DDI_FUNC_CTL_BFI_ENABLE           : constant := 1 * 2 **  4;
   PIPE_DDI_FUNC_CTL_PORT_WIDTH_MASK      : constant := 7 * 2 **  1;
   PIPE_DDI_FUNC_CTL_PORT_WIDTH_1_LANE    : constant := 0 * 2 **  1;
   PIPE_DDI_FUNC_CTL_PORT_WIDTH_2_LANES   : constant := 1 * 2 **  1;
   PIPE_DDI_FUNC_CTL_PORT_WIDTH_4_LANES   : constant := 3 * 2 **  1;

   type DDI_Select_Array is array (Digital_Port) of Word32;
   PIPE_DDI_FUNC_CTL_DDI_SELECT : constant DDI_Select_Array :=
      DDI_Select_Array'
     (DIGI_A => PIPE_DDI_FUNC_CTL_DDI_SELECT_NONE,
      DIGI_B => PIPE_DDI_FUNC_CTL_DDI_SELECT_B,
      DIGI_C => PIPE_DDI_FUNC_CTL_DDI_SELECT_C,
      DIGI_D => PIPE_DDI_FUNC_CTL_DDI_SELECT_D,
      DIGI_E => PIPE_DDI_FUNC_CTL_DDI_SELECT_E);

   type DDI_Mode_Array is array (Display_Type) of Word32;
   PIPE_DDI_FUNC_CTL_MODE_SELECT : constant DDI_Mode_Array :=
      DDI_Mode_Array'
     (VGA      => PIPE_DDI_FUNC_CTL_MODE_SELECT_FDI,
      HDMI     => PIPE_DDI_FUNC_CTL_MODE_SELECT_DVI,
      DP       => PIPE_DDI_FUNC_CTL_MODE_SELECT_DP_SST,
      others   => 0);

   type HV_Sync_Array is array (Boolean) of Word32;
   PIPE_DDI_FUNC_CTL_VSYNC : constant HV_Sync_Array := HV_Sync_Array'
     (False => PIPE_DDI_FUNC_CTL_VSYNC_ACTIVE_LOW,
      True  => PIPE_DDI_FUNC_CTL_VSYNC_ACTIVE_HIGH);
   PIPE_DDI_FUNC_CTL_HSYNC : constant HV_Sync_Array := HV_Sync_Array'
     (False => PIPE_DDI_FUNC_CTL_HSYNC_ACTIVE_LOW,
      True  => PIPE_DDI_FUNC_CTL_HSYNC_ACTIVE_HIGH);

   type EDP_Select_Array is array (Pipe_Index) of Word32;
   PIPE_DDI_FUNC_CTL_EDP_SELECT : constant EDP_Select_Array :=
     (Primary     => PIPE_DDI_FUNC_CTL_EDP_SELECT_ALWAYS_ON,   -- we never use
                                                               -- panel fitter
      Secondary   => PIPE_DDI_FUNC_CTL_EDP_SELECT_B,
      Tertiary    => PIPE_DDI_FUNC_CTL_EDP_SELECT_C);
   PIPE_DDI_FUNC_CTL_EDP_SELECT_ONOFF : constant EDP_Select_Array :=
     (Primary     => PIPE_DDI_FUNC_CTL_EDP_SELECT_A,
      Secondary   => PIPE_DDI_FUNC_CTL_EDP_SELECT_B,
      Tertiary    => PIPE_DDI_FUNC_CTL_EDP_SELECT_C);

   type Port_Width_Array is array (HW.GFX.DP_Lane_Count) of Word32;
   PIPE_DDI_FUNC_CTL_PORT_WIDTH : constant Port_Width_Array :=
      Port_Width_Array'
     (HW.GFX.DP_Lane_Count_1 => PIPE_DDI_FUNC_CTL_PORT_WIDTH_1_LANE,
      HW.GFX.DP_Lane_Count_2 => PIPE_DDI_FUNC_CTL_PORT_WIDTH_2_LANES,
      HW.GFX.DP_Lane_Count_4 => PIPE_DDI_FUNC_CTL_PORT_WIDTH_4_LANES);

   function PIPE_DDI_FUNC_CTL_BPC (BPC : HW.GFX.BPC_Type) return Word32
   is
      Result : Word32;
   begin
      case BPC is
         when      6 => Result := PIPE_DDI_FUNC_CTL_BPC_6BITS;
         when      8 => Result := PIPE_DDI_FUNC_CTL_BPC_8BITS;
         when     10 => Result := PIPE_DDI_FUNC_CTL_BPC_10BITS;
         when     12 => Result := PIPE_DDI_FUNC_CTL_BPC_12BITS;
         when others => Result := PIPE_DDI_FUNC_CTL_BPC_8BITS;
      end case;
      return Result;
   end PIPE_DDI_FUNC_CTL_BPC;

   function PIPE_DATA_M_TU (Transfer_Unit : Positive) return Word32 is
   begin
      return Shift_Left (Word32 (Transfer_Unit - 1), 25);
   end PIPE_DATA_M_TU;

   PIPE_MSA_MISC_SYNC_CLK     : constant := 1 * 2 ** 0;
   PIPE_MSA_MISC_BPC_6BITS    : constant := 0 * 2 ** 5;
   PIPE_MSA_MISC_BPC_8BITS    : constant := 1 * 2 ** 5;
   PIPE_MSA_MISC_BPC_10BITS   : constant := 2 * 2 ** 5;
   PIPE_MSA_MISC_BPC_12BITS   : constant := 3 * 2 ** 5;
   PIPE_MSA_MISC_BPC_16BITS   : constant := 4 * 2 ** 5;

   function PIPE_MSA_MISC_BPC (BPC : HW.GFX.BPC_Type) return Word32 is
      Result : Word32;
   begin
      case BPC is
         when      6 => Result := PIPE_MSA_MISC_BPC_6BITS;
         when      8 => Result := PIPE_MSA_MISC_BPC_8BITS;
         when     10 => Result := PIPE_MSA_MISC_BPC_10BITS;
         when     12 => Result := PIPE_MSA_MISC_BPC_12BITS;
         --when     16 => Result := PIPE_MSA_MISC_BPC_16BITS;
         when others => Result := PIPE_MSA_MISC_BPC_8BITS;
      end case;
      return Result;
   end PIPE_MSA_MISC_BPC;

   ---------------------------------------------------------------------------

   function PLANE_WM_LINES (Lines : Natural) return Word32 is
   begin
      return Shift_Left (Word32 (Lines), PLANE_WM_LINES_SHIFT)
               and PLANE_WM_LINES_MASK;
   end PLANE_WM_LINES;

   function PLANE_WM_BLOCKS (Blocks : Natural) return Word32 is
   begin
      return Word32 (Blocks) and PLANE_WM_BLOCKS_MASK;
   end PLANE_WM_BLOCKS;

   ---------------------------------------------------------------------------

   function Encode (LSW, MSW : Pos16) return Word32 is
   begin
      return Shift_Left (Word32 (MSW - 1), 16) or Word32 (LSW - 1);
   end Encode;

   ----------------------------------------------------------------------------

   procedure Setup_Link
     (Head  : Head_Type;
      Link  : DP_Link;
      Mode  : Mode_Type)
   with
      Global => (In_Out => Registers.Register_State),
      Depends => (Registers.Register_State =>+ (Head, Link, Mode))
   is
      Data_M, Link_M : DP_Info.M_Type;
      Data_N, Link_N : DP_Info.N_Type;
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      DP_Info.Calculate_M_N
        (Link     => Link,
         Mode     => Mode,
         Data_M   => Data_M,
         Data_N   => Data_N,
         Link_M   => Link_M,
         Link_N   => Link_N);

      Registers.Write
        (Register => Head.PIPE_DATA_M1,
         Value    => PIPE_DATA_M_TU (64) or
                     Word32 (Data_M));
      Registers.Write
        (Register => Head.PIPE_DATA_N1,
         Value    => Word32 (Data_N));

      Registers.Write
        (Register => Head.PIPE_LINK_M1,
         Value    => Word32 (Link_M));
      Registers.Write
        (Register => Head.PIPE_LINK_N1,
         Value    => Word32 (Link_N));

      if Config.Has_Pipe_MSA_Misc then
         Registers.Write
           (Register => Head.PIPE_MSA_MISC,
            Value    => PIPE_MSA_MISC_SYNC_CLK or
                        PIPE_MSA_MISC_BPC (Mode.BPC));
      end if;
   end Setup_Link;

   ----------------------------------------------------------------------------

   procedure Clear_Watermarks (Controller : Controller_Type) is
   begin
      Registers.Write
        (Register    => Controller.PLANE_BUF_CFG,
         Value       => 16#0000_0000#);
      for Level in WM_Levels range 0 .. WM_Levels'Last loop
         Registers.Write
           (Register => Controller.PLANE_WM (Level),
            Value    => 16#0000_0000#);
      end loop;
      Registers.Write
        (Register    => Controller.WM_LINETIME,
         Value       => 16#0000_0000#);
   end Clear_Watermarks;

   procedure Setup_Watermarks (Controller : Controller_Type)
   is
      type Per_Plane_Buffer_Range is array (Pipe_Index) of Word32;
      Buffer_Range : constant Per_Plane_Buffer_Range :=
        (Primary     => Shift_Left (159, 16) or   0,
         Secondary   => Shift_Left (319, 16) or 160,
         Tertiary    => Shift_Left (479, 16) or 320);
   begin
      Registers.Write
        (Register    => Controller.PLANE_BUF_CFG,
         Value       => Buffer_Range (Controller.Pipe));
      Registers.Write
        (Register    => Controller.PLANE_WM (0),
         Value       => PLANE_WM_ENABLE or
                        PLANE_WM_LINES (2) or
                        PLANE_WM_BLOCKS (160));
   end Setup_Watermarks;

   ----------------------------------------------------------------------------

   procedure Setup_Hires_Plane
     (Controller  : Controller_Type;
      Framebuffer : HW.GFX.Framebuffer_Type)
   with
      Global => (In_Out => Registers.Register_State),
      Depends =>
        (Registers.Register_State
            =>+
              (Registers.Register_State,
               Controller,
               Framebuffer))
   is
      -- FIXME: setup correct format, based on framebuffer RGB format
      Format : constant Word32 := 6 * 2 ** 26;
      PRI : Word32 := DSPCNTR_ENABLE or Format;

      function To_Bytes (Pixels : Width_Type) return Word32
      with
         Pre => (Word32 (Pixels) <= Word32'Last / 4 / Word32 (BPC_Type'Last) * 8)
      is
      begin
         return Word32 (Pos64 (Pixels) * 4 * Framebuffer.BPC / 8);
      end To_Bytes;
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      if Config.Has_Plane_Control then
         Registers.Write
           (Register    => Controller.PLANE_CTL,
            Value       => PLANE_CTL_PLANE_ENABLE or
                           PLANE_CTL_SRC_PIX_FMT_RGB_32B_8888 or
                           PLANE_CTL_PLANE_GAMMA_DISABLE);
         Registers.Write (Controller.PLANE_OFFSET, 16#0000_0000#);
         Registers.Write
           (Controller.PLANE_SIZE,
            Encode (Pos16 (Framebuffer.Width), Pos16 (Framebuffer.Height)));
         Registers.Write (Controller.PLANE_STRIDE, To_Bytes (Framebuffer.Stride) / 64);
         Registers.Write (Controller.PLANE_POS,    16#0000_0000#);
         Registers.Write (Controller.PLANE_SURF,   Framebuffer.Offset and 16#ffff_f000#);
      else
         if Config.Disable_Trickle_Feed then
            PRI := PRI or DSPCNTR_DISABLE_TRICKLE_FEED;
         end if;
         -- for now, just disable gamma LUT (can't do anything
         -- useful without colorimetry information from display)
         Registers.Unset_And_Set_Mask
            (Register   => Controller.DSPCNTR,
             Mask_Unset => DSPCNTR_MASK,
             Mask_Set   => PRI);

         Registers.Write (Controller.DSPSTRIDE, To_Bytes (Framebuffer.Stride));
         Registers.Write (Controller.DSPSURF, Framebuffer.Offset and 16#ffff_f000#);
         if Config.Has_DSP_Linoff then
            Registers.Write (Controller.DSPLINOFF, 0);
         end if;
         Registers.Write (Controller.DSPTILEOFF, 0);
      end if;
   end Setup_Hires_Plane;

   procedure Setup_Display
     (Controller  : Controller_Type;
      Framebuffer : Framebuffer_Type;
      Dither_BPC  : BPC_Type;
      Dither      : Boolean)
   with
      Global => (In_Out => (Registers.Register_State, Port_IO.State)),
      Depends =>
        (Registers.Register_State
            =>+
              (Registers.Register_State,
               Controller,
               Framebuffer,
               Dither_BPC,
               Dither),
         Port_IO.State
            =>+
               (Framebuffer))
   is
      use type Word8;

      Reg8 : Word8;
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      if Config.Has_Plane_Control then
         Setup_Watermarks (Controller);
      end if;

      if Framebuffer.Offset = VGA_PLANE_FRAMEBUFFER_OFFSET then
         if Config.VGA_Plane_Workaround then
            Registers.Unset_And_Set_Mask
              (Register    => Registers.ILK_DISPLAY_CHICKEN1,
               Mask_Unset  => ILK_DISPLAY_CHICKEN1_VGA_MASK,
               Mask_Set    => ILK_DISPLAY_CHICKEN1_VGA_ENABLE);
            Registers.Unset_And_Set_Mask
              (Register    => Registers.ILK_DISPLAY_CHICKEN2,
               Mask_Unset  => ILK_DISPLAY_CHICKEN2_VGA_MASK,
               Mask_Set    => ILK_DISPLAY_CHICKEN2_VGA_ENABLE);
         end if;

         Registers.Unset_And_Set_Mask
           (Register    => Registers.VGACNTRL,
            Mask_Unset  => VGA_CONTROL_VGA_DISPLAY_DISABLE or
                           VGA_CONTROL_BLINK_DUTY_CYCLE_MASK or
                           VGA_CONTROL_VSYNC_BLINK_RATE_MASK,
            Mask_Set    => VGA_CONTROL_BLINK_DUTY_CYCLE_50 or
                           VGA_CONTROL_VSYNC_BLINK_RATE (30));

         Port_IO.OutB (VGA_SR_INDEX, VGA_SR01);
         Port_IO.InB  (Reg8, VGA_SR_DATA);
         Port_IO.OutB (VGA_SR_DATA, Reg8 and not (VGA_SR01_SCREEN_OFF));
      else
         Setup_Hires_Plane (Controller, Framebuffer);
      end if;

      Registers.Write
        (Register => Controller.PIPESRC,
         Value    => Encode
           (Pos16 (Framebuffer.Height), Pos16 (Framebuffer.Width)));

      if Config.Has_Pipeconf_Misc then
         Registers.Write
           (Register => Controller.PIPEMISC,
            Value    => PIPECONF_Misc (Dither_BPC, Dither));
      end if;
   end Setup_Display;

   procedure Setup_Transcoder
     (Head     : Head_Type;
      Port_Cfg : Port_Config)
   is
      M : constant Mode_Type := Port_Cfg.Mode;
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      if Config.Has_Trans_Clk_Sel and then
         Head.TRANS_CLK_SEL /= Registers.Invalid_Register
      then
         Registers.Write
           (Register => Head.TRANS_CLK_SEL,
            Value    => TRANS_CLK_SEL_PORT (Port_Cfg.Port));
      end if;

      if Port_Cfg.Is_FDI then
         Setup_Link (Head, Port_Cfg.FDI, Port_Cfg.Mode);
      elsif Port_Cfg.Display = DP then
         Setup_Link (Head, Port_Cfg.DP, Port_Cfg.Mode);
      end if;

      Registers.Write (Head.HTOTAL,  Encode (M.H_Visible,    M.H_Total));
      Registers.Write (Head.HBLANK,  Encode (M.H_Visible,    M.H_Total));
      Registers.Write (Head.HSYNC,   Encode (M.H_Sync_Begin, M.H_Sync_End));
      Registers.Write (Head.VTOTAL,  Encode (M.V_Visible,    M.V_Total));
      Registers.Write (Head.VBLANK,  Encode (M.V_Visible,    M.V_Total));
      Registers.Write (Head.VSYNC,   Encode (M.V_Sync_Begin, M.V_Sync_End));
   end Setup_Transcoder;

   ----------------------------------------------------------------------------

   procedure Scale_Keep_Aspect
     (Width       :    out Pos32;
      Height      :    out Pos32;
      Max_Width   : in     Pos32;
      Max_Height  : in     Pos32;
      Framebuffer : in     Framebuffer_Type)
   with
      Pre =>
         Max_Width <= Pos32 (Pos16'Last) and
         Max_Height <= Pos32 (Pos16'Last) and
         Framebuffer.Width <= Max_Width and
         Framebuffer.Height <= Max_Height,
      Post =>
         Width <= Max_Width and Height <= Max_Height
   is
   begin
      if (Max_Width * Framebuffer.Height) / Framebuffer.Width <= Max_Height then
         Width  := Max_Width;
         Height := (Max_Width * Framebuffer.Height) / Framebuffer.Width;
      else
         Height := Max_Height;
         Width  := Pos32'Min (Max_Width,  -- could prove, it's <= Max_Width
            (Max_Height * Framebuffer.Width) / Framebuffer.Height);
      end if;
   end Scale_Keep_Aspect;

   procedure Setup_Skylake_Pipe_Scaler
     (Controller  : in     Controller_Type;
      Mode        : in     HW.GFX.Mode_Type;
      Framebuffer : in     HW.GFX.Framebuffer_Type)
   with
      Pre =>
         Framebuffer.Width <= Pos32 (Mode.H_Visible) and
         Framebuffer.Height <= Pos32 (Mode.V_Visible)
   is
      -- Enable 7x5 extended mode where possible:
      Scaler_Mode : constant Word32 :=
        (if Controller.PS_CTRL_2 /= Registers.Invalid_Register then
            PS_CTRL_SCALER_MODE_7X5_EXTENDED else 0);

      -- We can scale up to 2.99x horizontally:
      Horizontal_Limit : constant Pos32 := ((Framebuffer.Width * 299) / 100);
      -- The third scaler is limited to 1.99x
      -- vertical scaling for source widths > 2048:
      Vertical_Limit : constant Pos32 :=
        (Framebuffer.Height *
           (if Controller.PS_CTRL_2 = Registers.Invalid_Register and
               Framebuffer.Width > 2048
            then
               199
            else
               299)) / 100;

      Width, Height : Pos32;
   begin
      -- Writes to WIN_SZ arm the PS registers.

      Scale_Keep_Aspect
        (Width       => Width,
         Height      => Height,
         Max_Width   => Pos32'Min (Horizontal_Limit, Pos32 (Mode.H_Visible)),
         Max_Height  => Pos32'Min (Vertical_Limit, Pos32 (Mode.V_Visible)),
         Framebuffer => Framebuffer);

      Registers.Write
        (Register => Controller.PS_CTRL_1,
         Value    => PS_CTRL_ENABLE_SCALER or Scaler_Mode);
      Registers.Write
        (Register => Controller.PS_WIN_POS_1,
         Value    =>
            Shift_Left (Word32 (Pos32 (Mode.H_Visible) - Width) / 2, 16) or
            Word32 (Pos32 (Mode.V_Visible) - Height) / 2);
      Registers.Write
        (Register => Controller.PS_WIN_SZ_1,
         Value    => Shift_Left (Word32 (Width), 16) or Word32 (Height));
   end Setup_Skylake_Pipe_Scaler;

   procedure Setup_Ironlake_Panel_Fitter
     (Controller  : in     Controller_Type;
      Mode        : in     HW.GFX.Mode_Type;
      Framebuffer : in     HW.GFX.Framebuffer_Type)
   with
      Pre =>
         Framebuffer.Width <= Pos32 (Mode.H_Visible) and
         Framebuffer.Height <= Pos32 (Mode.V_Visible)
   is
      -- Force 1:1 mapping of panel fitter:pipe
      PF_Ctrl_Pipe_Sel : constant Word32 :=
        (if Config.Has_PF_Pipe_Select then
           (case Controller.PF_CTRL is
               when Registers.PFA_CTL_1 => 0 * 2 ** 29,
               when Registers.PFB_CTL_1 => 1 * 2 ** 29,
               when Registers.PFC_CTL_1 => 2 * 2 ** 29,
               when others              => 0) else 0);

      Width, Height : Pos32;
   begin
      -- Writes to WIN_SZ arm the PF registers.

      Scale_Keep_Aspect
        (Width       => Width,
         Height      => Height,
         Max_Width   => Pos32 (Mode.H_Visible),
         Max_Height  => Pos32 (Mode.V_Visible),
         Framebuffer => Framebuffer);

      Registers.Write
        (Register => Controller.PF_CTRL,
         Value    => PF_CTRL_ENABLE or PF_Ctrl_Pipe_Sel or PF_CTRL_FILTER_MED);
      Registers.Write
        (Register => Controller.PF_WIN_POS,
         Value    =>
            Shift_Left (Word32 (Pos32 (Mode.H_Visible) - Width) / 2, 16) or
            Word32 (Pos32 (Mode.V_Visible) - Height) / 2);
      Registers.Write
        (Register => Controller.PF_WIN_SZ,
         Value    => Shift_Left (Word32 (Width), 16) or Word32 (Height));
   end Setup_Ironlake_Panel_Fitter;

   procedure Setup_Scaling
     (Controller  : in     Controller_Type;
      Mode        : in     HW.GFX.Mode_Type;
      Framebuffer : in     HW.GFX.Framebuffer_Type)
   with
      Pre =>
         Framebuffer.Width <= Pos32 (Mode.H_Visible) and
         Framebuffer.Height <= Pos32 (Mode.V_Visible)
   is
   begin
      if Framebuffer.Width /= Pos32 (Mode.H_Visible) or
         Framebuffer.Height /= Pos32 (Mode.V_Visible)
      then
         if Config.Has_Plane_Control then
            Setup_Skylake_Pipe_Scaler (Controller, Mode, Framebuffer);
         else
            Setup_Ironlake_Panel_Fitter (Controller, Mode, Framebuffer);
         end if;
      end if;
   end Setup_Scaling;

   ----------------------------------------------------------------------------

   procedure Transcoder_On
     (Pipe        : Pipe_Index;
      Head        : Head_Type;
      Port_Cfg    : Port_Config;
      Dither      : Boolean)
   is
   begin
      if Config.Has_Pipe_DDI_Func then
         Registers.Write
           (Register => Head.PIPE_DDI_FUNC_CTL,
            Value    => PIPE_DDI_FUNC_CTL_ENABLE or
                        PIPE_DDI_FUNC_CTL_DDI_SELECT (Port_Cfg.Port) or
                        PIPE_DDI_FUNC_CTL_MODE_SELECT (Port_Cfg.Display) or
                        PIPE_DDI_FUNC_CTL_BPC (Port_Cfg.Mode.BPC) or
                        PIPE_DDI_FUNC_CTL_VSYNC (Port_Cfg.Mode.V_Sync_Active_High) or
                        PIPE_DDI_FUNC_CTL_HSYNC (Port_Cfg.Mode.H_Sync_Active_High) or
                        PIPE_DDI_FUNC_CTL_EDP_SELECT (Pipe) or
                        PIPE_DDI_FUNC_CTL_PORT_WIDTH (Port_Cfg.DP.Lane_Count));
      end if;

      Registers.Write
        (Register => Head.PIPECONF,
         Value    => PIPECONF_ENABLE or
                     (if not Config.Has_Pipeconf_Misc then
                        PIPECONF_Misc (Port_Cfg.Mode.BPC, Dither) else 0));
      Registers.Posting_Read (Head.PIPECONF);
   end Transcoder_On;

   ----------------------------------------------------------------------------

   procedure On
     (Pipe        : Pipe_Index;
      Port_Cfg    : Port_Config;
      Framebuffer : Framebuffer_Type)
   is
      -- Enable dithering if framebuffer BPC differs from port BPC,
      -- as smooth gradients look really bad without.
      Dither : constant Boolean := Framebuffer.BPC /= Port_Cfg.Mode.BPC;
      Head : constant Pipe_Head := Get_Pipe_Head (Pipe, Port_Cfg.Port);
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      Setup_Transcoder (Heads (Head), Port_Cfg);

      Setup_Display
        (Controllers (Pipe), Framebuffer, Port_Cfg.Mode.BPC, Dither);

      Setup_Scaling (Controllers (Pipe), Port_Cfg.Mode, Framebuffer);

      Transcoder_On (Pipe, Heads (Head), Port_Cfg, Dither);
   end On;

   ----------------------------------------------------------------------------

   procedure Planes_Off (Controller : Controller_Type) is
   begin
      Registers.Unset_Mask (Controller.SPCNTR, SPCNTR_ENABLE);
      if Config.Has_Plane_Control then
         Clear_Watermarks (Controller);
         Registers.Unset_Mask (Controller.PLANE_CTL, PLANE_CTL_PLANE_ENABLE);
         Registers.Write (Controller.PLANE_SURF, 16#0000_0000#);
      else
         Registers.Unset_Mask (Controller.DSPCNTR, DSPCNTR_ENABLE);
      end if;
   end Planes_Off;

   procedure Head_Off (Head : Head_Type)
   is
      Enabled : Boolean;
   begin
      Registers.Is_Set_Mask (Head.PIPECONF, PIPECONF_ENABLE, Enabled);

      if Enabled then
         Registers.Unset_Mask (Head.PIPECONF, PIPECONF_ENABLE);
      end if;

      -- Workaround for Broadwell:
      -- Status may be wrong if pipe hasn't been enabled since reset.
      if not Config.Pipe_Enabled_Workaround or else Enabled then
         -- synchronously wait until pipe is truly off
         Registers.Wait_Unset_Mask
           (Register => Head.PIPECONF,
            Mask     => PIPECONF_ENABLED_STATUS,
            TOut_MS  => 40);
      end if;

      if Config.Has_Pipe_DDI_Func then
         Registers.Write (Head.PIPE_DDI_FUNC_CTL, 0);
      end if;
   end Head_Off;

   procedure Transcoder_Off (Pipe : Pipe_Index)
   is
      DDI_Func_Ctl : Word32;
   begin
      if Config.Has_EDP_Pipe then
         Registers.Read (Registers.PIPE_EDP_DDI_FUNC_CTL, DDI_Func_Ctl);
         DDI_Func_Ctl := DDI_Func_Ctl and PIPE_DDI_FUNC_CTL_EDP_SELECT_MASK;

         if (Pipe = Primary and
             DDI_Func_Ctl = PIPE_DDI_FUNC_CTL_EDP_SELECT_ALWAYS_ON) or
            DDI_Func_Ctl = PIPE_DDI_FUNC_CTL_EDP_SELECT_ONOFF (Pipe)
         then
            Head_Off (Heads (Head_EDP));
         end if;
      end if;

      Head_Off (Heads (Default_Pipe_Head (Pipe)));
   end Transcoder_Off;

   procedure Panel_Fitter_Off (Controller : Controller_Type) is
   begin
      -- Writes to WIN_SZ arm the PS/PF registers.
      if Config.Has_Plane_Control then
         Registers.Unset_Mask (Controller.PS_CTRL_1, PS_CTRL_ENABLE_SCALER);
         Registers.Write (Controller.PS_WIN_SZ_1, 16#0000_0000#);
         if Controller.PS_CTRL_2 /= Registers.Invalid_Register and
            Controller.PS_WIN_SZ_2 /= Registers.Invalid_Register
         then
            Registers.Unset_Mask (Controller.PS_CTRL_2, PS_CTRL_ENABLE_SCALER);
            Registers.Write (Controller.PS_WIN_SZ_2, 16#0000_0000#);
         end if;
      else
         Registers.Unset_Mask (Controller.PF_CTRL, PF_CTRL_ENABLE);
         Registers.Write (Controller.PF_WIN_SZ, 16#0000_0000#);
      end if;
   end Panel_Fitter_Off;

   procedure Trans_Clk_Off (Head : Head_Type) is
   begin
      if Config.Has_Trans_Clk_Sel and then
         Head.TRANS_CLK_SEL /= Registers.Invalid_Register
      then
         Registers.Write (Head.TRANS_CLK_SEL, TRANS_CLK_SEL_PORT_NONE);
      end if;
   end Trans_Clk_Off;

   procedure Off (Pipe : Pipe_Index; Port_Cfg : Port_Config)
   is
      Head : constant Pipe_Head := Get_Pipe_Head (Pipe, Port_Cfg.Port);
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      Planes_Off (Controllers (Pipe));
      Transcoder_Off (Pipe);
      Panel_Fitter_Off (Controllers (Pipe));
      Trans_Clk_Off (Heads (Head));
   end Off;

   procedure Legacy_VGA_Off
   is
      use type HW.Word8;
      Reg8 : Word8;
   begin
      Port_IO.OutB (VGA_SR_INDEX, VGA_SR01);
      Port_IO.InB  (Reg8, VGA_SR_DATA);
      Port_IO.OutB (VGA_SR_DATA, Reg8 or VGA_SR01_SCREEN_OFF);
      Time.U_Delay (100); -- PRM says 100us, Linux does 300
      Registers.Set_Mask (Registers.VGACNTRL, VGA_CONTROL_VGA_DISPLAY_DISABLE);
   end Legacy_VGA_Off;

   procedure All_Off
   is
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      Legacy_VGA_Off;

      for Pipe in Pipe_Index loop
         Planes_Off (Controllers (Pipe));
         Transcoder_Off (Pipe);
         Panel_Fitter_Off (Controllers (Pipe));
         Trans_Clk_Off (Heads (Default_Pipe_Head (Pipe)));
      end loop;
   end All_Off;

   ----------------------------------------------------------------------------

   procedure Update_Offset (Pipe : Pipe_Index; Framebuffer : Framebuffer_Type)
   is
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      Registers.Write
        (Controllers (Pipe).DSPSURF, Framebuffer.Offset and 16#ffff_f000#);
   end Update_Offset;

   ----------------------------------------------------------------------------

   function Get_Pipe_Hint (Pipe : Pipe_Index) return Word32
   is
   begin
      return
        (case Pipe is
            when Primary      => 0,
            when Secondary    => 1,
            when Tertiary     => 2);
   end Get_Pipe_Hint;

end HW.GFX.GMA.Pipe_Setup;
