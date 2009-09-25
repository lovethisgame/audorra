{*******************************************************}
{                                                       }
{       Audorra Digital Audio Library                   }
{       Copyright (c) Andreas St�ckel, 2009             }
{       Audorra is an "Andorra Suite" Project           }
{                                                       }
{*******************************************************}

{The contents of this file are subject to the Mozilla Public License Version 1.1
(the "License"); you may not use this file except in compliance with the
License. You may obtain a copy of the License at http://www.mozilla.org/MPL/

Software distributed under the License is distributed on an "AS IS" basis,
WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for
the specific language governing rights and limitations under the License.

The Initial Developer of the Original Code is
Andreas St�ckel. All Rights Reserved.

Alternatively, the contents of this file may be used under the terms of the
GNU General Public License license (the �GPL License�), in which case the provisions of
GPL License are applicable instead of those above. If you wish to allow use
of your version of this file only under the terms of the GPL License and not
to allow others to use your version of this file under the MPL, indicate your
decision by deleting the provisions above and replace them with the notice and
other provisions required by the GPL License. If you do not delete the
provisions above, a recipient may use your version of this file under either the
MPL or the GPL License.

File: AuWaveOut32Driver.pas
Author: Andreas St�ckel
}

{Software output driver for the low level windows "WaveOut" interface.}
unit AuWaveOut32Driver;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  Classes, Windows, MMSystem,
  AcPersistent,
  AuTypes, AuDriverClasses;

type
  TWaveFormatExtensible = record
    Format : tWAVEFORMATEX;

    wValidBitsPerSample : Word;
    dwChannelMask : DWord;
    SubFormat : TGuid;
  end;

  PWaveFormatExtensible = ^TWaveFormatExtensible;

  PWaveHdr = ^TWaveHdr;

  TAuWaveOutDriver = class(TAuDriver)
    public
      procedure EnumDevices(ACallback: TAuEnumDeviceProc);override;

      function CreateStaticSoundDriver(ADeviceID: integer;
        AParameters: TAuAudioParametersEx;
        AScene: TAu3DScene = nil): TAuStaticSoundDriver;override;

      function CreateStreamDriver(ADeviceID: integer;
        AParameters: TAuAudioParametersEx;
        AScene: TAu3DScene = nil): TAuStreamDriver;override;

      function Create3DScene: TAu3DScene;override;       
  end;

  TAuWaveOutStaticSoundDriver = class(TAuStaticSoundDriver)
    private
      FHWO: HWAVEOUT;
      FFormat: TWaveFormatExtensible;
      FDevID: Cardinal;
      FBlock: TWaveHdr;
      FBuf: PByte;
      FSize: Cardinal;
      FWroteHeader: boolean;
      procedure WriteHeader;
    public
      {Creates a new instance of TAuWaveOutStaticSoundDriver.
       @param(AID is the device id.)
       @param(AFmt is the windows wave format descriptor.)}
      constructor Create(AID: Cardinal; AFmt: TWaveFormatExtensible);

      {Destroys the instance of TAuWaveOutStaticSoundDriver.}
      destructor Destroy;override;

      {Starts the audio playback.}
      procedure Play;override;
      {Pauses the audio playback.}
      procedure Pause;override;      
      {Stops audio playback: All loaded audio buffers are cleaned up.}
      procedure Stop;override;
      {Openes the audio object. And prepares it for playback. When using the
       TAuStaticSoundDriver, data can now be written into the object.}
      function Open: boolean;override;
      {Closes the audio object.}
      procedure Close;override;

      {After the audio object has been opened, the WriteData function can be used
       to write data into its sound buffer. Remember that the length of this audio
       data shouldn't be too long. A justifiable value is 10 seconds, an absolute
       maximum should be one minute.
       The data is not copied to the driver object, the data has to be available
       until the sound object is freed.}
      procedure WriteData(ABuf: PByte; ASize: Cardinal);override;

      procedure NotifyStop;
  end;

  TAuWaveOutStreamDriver = class(TAuStreamDriver)
    private
      FHWO: HWAVEOUT;
      FDevId: integer;
      FFormat: TWaveFormatExtensible;
      FBlocks: array of TWaveHdr;
      FBuffer: PByte;
      FBlockCount: Cardinal;
      FBlockSize: Cardinal;
      FCurrentblock: Cardinal;
      FFreeblocks: Cardinal;
      FSyncDataArr: array of TAuSyncData;
      procedure AllocBlocks(ABlockCount, ABlockSize: Cardinal);
      procedure DestroyBlocks;
    public
      {Creates a new instance of TAuWaveOutStaticSoundDriver.
       @param(AID is the device id.)
       @param(AFmt is the windows wave format descriptor.)}
      constructor Create(AID: Cardinal; AFmt: TWaveFormatExtensible);

      {Destroys the instance of TAuWaveOutStaticSoundDriver.}
      destructor Destroy;override;

      {Starts the audio playback.}
      procedure Play;override;
      {Pauses the audio playback.}
      procedure Pause;override;      
      {Stops audio playback: All loaded audio buffers are cleaned up.}
      procedure Stop;override;
      {Openes the audio object. And prepares it for playback. When using the
       TAuStaticSoundDriver, data can now be written into the object.}
      function Open: boolean;override;
      {Closes the audio object.}
      procedure Close;override;

      procedure Idle(ACallback: TAuReadCallback);override;
  end;

var
  WaveOut_StdBlockCount: integer = 8;
  WaveOut_SamplesPerBlock: integer = 1024;

implementation

function CreateWaveOutDriver: TAuDriver;
begin
  result := TAuWaveOutDriver.Create;
end;

{ WaveOut helper functions}

const
  //GUID needed for multi channel audio output
  KSDATAFORMAT_SUBTYPE_PCM: TGUID = '{00000001-0000-0010-8000-00aa00389b71}';
  WAVE_FORMAT_EXTENSIBLE = $FFFE;
  SPEAKER_ALL = $FFFFFFFF;

function GetWaveFormatEx(AParameters: TAuAudioParametersEx): TWaveFormatExtensible;
begin
  //Fill the result record with zeros
  FillChar(result, SizeOf(result), #0);

  with AParameters do
  begin           
    //Copy wave format description into the wav_fmt buffer

    //Set channel count, sample rate and bit depth
    result.Format.nChannels := Channels;
    result.Format.nSamplesPerSec := Frequency;
    result.Format.wBitsPerSample := BitDepth;

    //Calculate needed "Bytes Per Second" value
    result.Format.nAvgBytesPerSec := (BitDepth div 8) * (Channels * Frequency);

    //Set the size of a single block
    result.Format.nBlockAlign := (BitDepth div 8 * Channels);

    if Channels > 2 then
    begin
      //As we have more than two audio channels, we have to use another wave format
      //descriptor
      result.Format.wFormatTag := WAVE_FORMAT_EXTENSIBLE;
      result.Format.cbSize := 22;

      //Set the bit depth mask
      result.wValidBitsPerSample := BitDepth;

      //Set the speakers that should be used
      result.dwChannelMask := SPEAKER_ALL;

      //We're still sending PCM data to the driver
      result.SubFormat := KSDATAFORMAT_SUBTYPE_PCM;
    end else
      //We only have two or one channels, so we're using the simple WaveFormatPCM
      //format descriptor
      result.Format.wFormatTag := WAVE_FORMAT_PCM;
  end;
end; 

{ TAuWaveOutDriver }

procedure TAuWaveOutDriver.EnumDevices(ACallback: TAuEnumDeviceProc);
var
  device: TAuDevice;
  num: Cardinal;
  i: Cardinal;
  caps: TWaveOutCapsA;  
begin
  device.UserData := nil;

  //Add the default device
  device.Name := 'Default Wave Mapper';
  device.ID := Integer(WAVE_MAPPER);
  device.Priority := 1;
  ACallback(device);

  //Enumerate all other devices
  device.Priority := 0;

  num := waveOutGetNumDevs;
  for i := 0 to num - 1 do
  begin
    if waveOutGetDevCaps(i, @caps, SizeOf(Caps)) = MMSYSERR_NOERROR then
    begin
      device.ID := i;
      device.Name := caps.szPname;

      ACallback(device);
    end;
  end;    
end;

function TAuWaveOutDriver.Create3DScene: TAu3DScene;
begin
  //The wave out driver doesn't support 3D sound at the moment.
  result := nil;
end;

function TAuWaveOutDriver.CreateStaticSoundDriver(ADeviceID: integer;
  AParameters: TAuAudioParametersEx; AScene: TAu3DScene): TAuStaticSoundDriver;
begin
  result := TAuWaveOutStaticSoundDriver.Create(Cardinal(ADeviceID),
    GetWaveFormatEx(AParameters));
end;

function TAuWaveOutDriver.CreateStreamDriver(ADeviceID: integer;
  AParameters: TAuAudioParametersEx; AScene: TAu3DScene): TAuStreamDriver;
begin
  result := TAuWaveOutStreamDriver.Create(Cardinal(ADeviceID),
    GetWaveFormatEx(AParameters));
end;

{ TAuWaveOutStaticSoundDriver }

procedure static_callback(hwo: HWAVEOUT; uMsg: Cardinal; dwInstance, dwParam1, dwParam2: DWORD);stdcall;
begin
  if (uMsg = WOM_DONE) then
    TAuWaveOutStaticSoundDriver(Pointer(dwInstance)).NotifyStop;
end;

constructor TAuWaveOutStaticSoundDriver.Create(AID: Cardinal;
  AFmt: TWaveFormatExtensible);
begin
  inherited Create;

  FHWO := 0;
  FFormat := AFmt;
  FDevID := AID;
end;

destructor TAuWaveOutStaticSoundDriver.Destroy;
begin
  Close;

  inherited;
end;

procedure TAuWaveOutStaticSoundDriver.NotifyStop;
begin
  FState := audsOpened;
  FWroteHeader := false;
  if Assigned(FStopProc) then
    FStopProc(self);
end;

procedure TAuWaveOutStaticSoundDriver.Close;
begin
  if FHWO <> 0 then
  begin
    //Stop any playback process
    Stop;

{    while (waveOutUnprepareHeader(FHWO, FBlock, SizeOf(FBlock)) = WAVERR_STILLPLAYING) do
      Sleep(1);             }

    while waveOutClose(FHWO) = WAVERR_STILLPLAYING do
      Sleep(1);

    //Set the wave out handle to zero
    FHWO := 0;
  end;

  FState := audsClosed;
end;

function TAuWaveOutStaticSoundDriver.Open: boolean;
begin
  //Close the waveout interface
  Close;

  result := false;

  //Try to open the wave out interface
  if waveOutOpen(@FHWO, FDevID, @FFormat,
    Cardinal(@static_callback),
    Cardinal(self), CALLBACK_FUNCTION) = MMSYSERR_NOERROR then
  begin    
    result := true;
    FState := audsOpened;
  end;
end;

procedure TAuWaveOutStaticSoundDriver.Pause;
begin
  waveOutPause(FHWO);
  FState := audsPaused;
end;

procedure TAuWaveOutStaticSoundDriver.Play;
begin
  if FState < audsPlaying then
  begin
    if not FWroteHeader then
      WriteHeader;

    FState := audsPlaying;

    waveOutRestart(FHWO);
  end;
end;

procedure TAuWaveOutStaticSoundDriver.Stop;
begin
  if FHWO <> 0 then
  begin
    waveOutReset(FHWO);
    FState := audsOpened;
    FWroteHeader := false;
  end;                      
end;

procedure TAuWaveOutStaticSoundDriver.WriteData(ABuf: PByte; ASize: Cardinal);
begin
  if FState = audsOpened then
  begin
    FBuf := ABuf;
    FSize := ASize;

    FWroteHeader := false;

//    WriteHeader;
  end;
  //! else Raise exception or return value
end;

procedure TAuWaveOutStaticSoundDriver.WriteHeader;
begin
  //Fill the header with zeros
  FillChar(FBlock, SizeOf(FBlock), #0);

  //Set the data pointer and the data length
  FBlock.lpData := PAnsiChar(FBuf);
  FBlock.dwBufferLength := FSize;

  //Set the loop property
  if FLoop then
  begin
    FBlock.dwFlags := WHDR_BEGINLOOP or WHDR_ENDLOOP;
    FBlock.dwLoops := High(Cardinal);
  end;

  //Prepare the header
  waveOutPrepareHeader(FHWO, @FBlock, SizeOf(FBlock));

  //Write the to the audio device
  waveOutWrite(FHWO, @FBlock, SizeOf(FBlock));

  FWroteHeader := true;
end;

{ TAuWaveOutStreamDriver }

procedure stream_callback(hwo: HWAVEOUT; uMsg: Cardinal; dwInstance, dwParam1, dwParam2: DWORD);stdcall;
begin
  if (uMsg = WOM_DONE) then
  begin
    with TAuWaveOutStreamDriver(Pointer(dwInstance)) do
      FFreeblocks := FFreeblocks + 1;
  end;
end;

constructor TAuWaveOutStreamDriver.Create(AID: Cardinal;
  AFmt: TWaveFormatExtensible);
begin
  inherited Create;

  FDevId := Integer(AID);
  FFormat := AFmt;
  FParameters.Frequency := AFmt.Format.nSamplesPerSec;
  FParameters.Channels := AFmt.Format.nChannels;
  FParameters.BitDepth := AFmt.Format.wBitsPerSample;
end;

destructor TAuWaveOutStreamDriver.Destroy;
begin
  Close;
  DestroyBlocks;

  inherited;
end;

procedure TAuWaveOutStreamDriver.Close;
var
  i: integer;
begin
  if FHWO <> 0 then
  begin
    waveOutReset(FHWO);
    
    for i := 0 to FBlockCount - 1 do
      if FBlocks[i].dwFlags = WHDR_PREPARED then
        while (waveOutUnprepareHeader(FHWO, @FBlocks[i], SizeOf(FBlocks[i])) = WAVERR_STILLPLAYING) do
          Sleep(1);

    while waveOutClose(FHWO) = WAVERR_STILLPLAYING do
      Sleep(1);

    DestroyBlocks;

    waveOutClose(FHWO);
    DestroyBlocks;
  end;

  FHWO := 0;
  FState := audsClosed;
end;

procedure TAuWaveOutStreamDriver.Idle(ACallback: TAuReadCallback);
begin
  if (FFreeblocks > 0) and (FHwo <> 0) and (FBlockCount > 0) then
  begin
    with FBlocks[FCurrentBlock] do
    begin
      if dwFlags = WHDR_PREPARED then
        waveOutUnprepareHeader(Fhwo, @FBlocks[FCurrentBlock], SizeOf(FBlocks[FCurrentBlock]));

      //Set the sync data
      FSyncData := FSyncDataArr[FCurrentBlock];
      
      dwBufferLength := ACallback(PByte(lpData), FBlockSize, FSyncDataArr[FCurrentBlock]);

      if dwBufferLength > 0 then
      begin
        waveOutPrepareHeader(Fhwo, @FBlocks[FCurrentBlock], SizeOf(FBlocks[FCurrentBlock]));
        waveOutWrite(Fhwo, @FBlocks[FCurrentBlock], SizeOf(FBlocks[FCurrentBlock]));

        dec(FFreeblocks);

        FCurrentBlock := FCurrentBlock + 1;
        if FBlockCount > 0 then        
          FCurrentBlock := FCurrentBlock mod FBlockcount;
      end;
    end;
  end;
end;

function TAuWaveOutStreamDriver.Open: boolean;
begin
  result := false;

  //Try to open wave out for streaming purposes
  if waveOutOpen(@Fhwo, Cardinal(FDevId), @FFormat, Cardinal(@stream_callback), Cardinal(self),
    CALLBACK_FUNCTION) = MMSYSERR_NOERROR then
  begin
    result := true;
    FState := audsOpened;

    //Pause the playback
    Pause;

    //Allocate buffer blocks
    AllocBlocks(
      WaveOut_StdBlockCount,
      WaveOut_SamplesPerBlock * FFormat.Format.nChannels * FFormat.Format.wBitsPerSample div 8);
  end;
end;

procedure TAuWaveOutStreamDriver.Pause;
begin
  if FHWO <> 0 then
  begin
    waveOutPause(FHWO);
    FState := audsPaused;
  end;
end;

procedure TAuWaveOutStreamDriver.Play;
begin
  if FHWO <> 0 then
  begin
    waveOutRestart(FHWO);
    FState := audsPlaying;
  end;
end;

procedure TAuWaveOutStreamDriver.Stop;
begin
  if FHWO <> 0 then
  begin
    waveOutReset(FHWO);
    waveOutPause(FHWO);

    FFreeblocks := FBlockCount;
    FCurrentblock := 0;
    FSyncData.Timecode := 0;
    FSyncData.FrameType := auftBeginning;
    FState := audsOpened;
  end;
end;

procedure TAuWaveOutStreamDriver.AllocBlocks(ABlockCount, ABlockSize: Cardinal);
var
  ptr: PByte;
  i: integer;
begin
  DestroyBlocks;

  FBlockCount := ABlockCount;
  FBlockSize := ABlockSize;

  //Reserve memory for the buffers
  GetMem(FBuffer, FBlocksize * FBlockcount);

  //Reserve memory for the FBuffer headers (FBlocks)
  SetLength(FBlocks, FBlockcount);

  //Reserve memory for the sync data array
  SetLength(FSyncDataArr, FBlockCount);

  ptr := FBuffer;
  for i := 0 to FBlockcount - 1 do
  begin
    FBlocks[i].lpData := PAnsiChar(ptr);
    FBlocks[i].dwUser := Cardinal(@FSyncDataArr[i]);
    FBlocks[i].dwBufferLength := FBlocksize;
    inc(ptr, FBlocksize);
  end;

  FFreeblocks := FBlockcount;
  FCurrentblock := 0;
end;

procedure TAuWaveOutStreamDriver.DestroyBlocks;
begin
  if FBuffer <> nil then
    FreeMem(FBuffer);

  FBuffer := nil;
  SetLength(FBlocks, 0);
  
  FBlockCount := 0;
  FBlockSize := 0;
end;

initialization
  AcRegSrv.RegisterClass(TAuWaveOutDriver, @CreateWaveOutDriver);

end.
