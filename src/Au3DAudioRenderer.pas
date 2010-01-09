{
  Audorra Digital Audio Library - 3D Rendering Library
  Copyright (C) 2009 Andreas St�ckel

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.

File: Au3DAudioRenderer.pas
Author: Andreas St�ckel
}
{This file contains an efficient 3d audio software renderer which is capable
 of calculating phase/dopplereffect, absorption and more.}
unit Au3DAudioRenderer;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  SysUtils, Classes, Math,
  AcMath, AcTypes, AcSyncObjs,
  AuTypes, AuUtils, AuAudioSpline, AuSyncUtils, Au3DRingBuffer;

const
  AU3DPROP_PHASE = $01;
  AU3DPROP_GAIN = $02;
  AU3DPROP_ALL = $FF;

type
  //Speaker setup presets
  TAu3DSpeakerPreset = (
    au3dssMono = 1,
    au3dssStereo = 2,
    au3dssQuadraphonic = 4,
    au3dss51 = 6,
    au3dss71 = 8
  );

  TAu3DChannelMatrix = array of array of Single;

  TAu3DSpeaker = (
    au3dspCenter = 0,
    au3dspFrontLeft = -1,
    au3dspFrontRight = 1,
    au3dspSideLeft = -2,
    au3dspSideRight = 2,
    au3dspRearLeft = -3,
    au3dspRearRight = 3,
    au3dspSubwoofer = 100
  );

  TAu3DSpeakerSetting = record
    angle: Single;
    speaker: TAu3DSpeaker;    
  end;

  TAu3DSpeakerSettings = array of TAu3DSpeakerSetting;

  TAu3DChannelMapper = class
    private
      FChannelMatrix: TAu3DChannelMatrix;
      FSpeakerSettings: TAu3DSpeakerSettings;
      FChannelLayout: array of TAu3DSpeaker;
      FOutCount: integer;
      procedure IntBuildMatrix;
    public
      constructor Create;
      destructor Destroy;override;

      procedure BuildMatrix(ASettings: TAu3DSpeakerSettings; AOutCount: integer);overload;
      procedure BuildMatrix(AInCount, AOutCount: integer);overload;

      procedure Map(AIn: PSingle; var AOut: PSingle; AClear: boolean);

      property OutCount: integer read FOutCount;
  end;

  TAu3DSpeakerSetup = class
    private
      FChannelCount: integer;
      FOutputChannelCount: integer;
      FSpeakers: TAu3DSpeakerSettings;
      FTableSize: integer;
      FSpeakerPreset: TAu3DSpeakerPreset;
      FSpeakerFactors: array of array of Extended;
      FMapper: TAu3DChannelMapper;
      procedure LoadPreset(APreset: TAu3DSpeakerPreset);
      procedure CalcFacTable(ACount: integer);
    public
      constructor Create(ASpeakerPreset: TAu3DSpeakerPreset);
      destructor Destroy;override;

      function MultFac(AChannel: integer; AAngle: Single): Single;
      
      property ChannelCount: integer read FChannelCount;
      property OutputChannelCount: integer read FOutputChannelCount;
      property Mapper: TAu3DChannelMapper read FMapper;
      property Speakers: TAu3DSpeakerSettings read FSpeakers;
  end;

  TAu3DCustomEmitter = class;

  TAu3DEmitterList = class(TList)
    private
      function GetItem(AIndex: integer): TAu3DCustomEmitter;
    protected
      procedure Notify(ptr: Pointer; action: TListNotification);override;
    public
      property Items[AIndex: integer]: TAu3DCustomEmitter read GetItem; default;
  end;

  TAu3DCustomSound = class
    private
      FAutoFree: Boolean;
      FEmitters: TAu3DEmitterList;
      FParameters: TAuAudioParameters;
      FMapper: TAu3DChannelMapper;
      FActive: Boolean;
      FBufferSamples: Integer;
      FRing: TAu3DAudioRingBuffer;
    public
      constructor Create(AParameters: TAuAudioParameters; ASamples: Integer);
      destructor Destroy;override;

      procedure Move(ATimeGap: Extended);virtual;abstract;

      procedure ClearBuffers;virtual;

      property AutoFree: Boolean read FAutoFree write FAutoFree;
      property Emitters: TAu3DEmitterList read FEmitters;
      property Ring: TAu3DAudioRingBuffer read FRing;
      property Parameters: TAuAudioParameters read FParameters;
      property Mapper: TAu3DChannelMapper read FMapper;
      property Active: Boolean read FActive write FActive;
      property BufferSamples: Integer read FBufferSamples;
  end;

  TAu3DStreamedSound = class(TAu3DCustomSound)
    private
      FPitch: Single;
      FTimePosition64: TAuSamplestamp;
      FCallback: TAuReadCallback;
      FBuf: PByte;
      FBufSize: Cardinal;

      procedure SetPitch(AValue: Single);
      procedure ReadSamples(ACount: Cardinal);
    public
      constructor Create(ACallback: TAuReadCallback;
        const AParameters: TAuAudioParameters; ABufferTime: Single = 5.0);
      destructor Destroy;override;

      procedure ClearBuffers;override;

      procedure Move(ATimeGap: Extended);override;     

      property Pitch: Single read FPitch write SetPitch;
      property TimePosition: TAuSampleStamp read FTimePosition64;
  end;

  TAu3DStaticSound = class(TAu3DCustomSound)
    private
      FLoop: Boolean;   
      procedure SetLoop(AValue: Boolean);
    public
      constructor Create(ABuf: PByte; ASamples: Cardinal;
        const AParameters: TAuAudioParameters);
      destructor Destroy;override;

      procedure Move(ATimeGap: Extended);override;
      procedure ClearBuffers;override;

      property Loop: Boolean read FLoop write SetLoop;
  end;

  TAu3DEmitterProc = procedure(AEmitter: TAu3DCustomEmitter;
    ATimeGap: Double) of object;

  TAu3DCustomEmitter = class
    private
      FAutoFree: Boolean;
      FMoveProc: TAu3DEmitterProc;
      FSound: TAu3DCustomSound;
      FActive: Boolean;
      FGlobalEmitter: Boolean;

      FPosition: TAuVector3;
      FGain: Single;
      FRolloffFactor: Single;
      FMaxDistance: Single;
      FReferenceDistance: Single;
      
      FProperties: Byte;

      procedure SetGain(AValue: Single);
      procedure SetRolloff(AValue: Single);
      procedure SetMaxDistance(AValue: Single);
      procedure SetReferenceDistance(AValue: Single);
    protected
      FTimeOffset: TAuSamplestamp;
      FManualPositionChange: Boolean;
      function GetPitch: Single;virtual;abstract;
      procedure SetPitch(AValue: Single);virtual;abstract;
    public
      constructor Create(ASound: TAu3DCustomSound);
      destructor Destroy;override;

      procedure Move(ATimeGap: Extended);virtual;abstract;       
      function TimePosition64: TAuSampleStamp;virtual;abstract;

      function TellSecond: Single;
      function TellSample: Integer;

      property Sound: TAu3DCustomSound read FSound;
      property Position: TAuVector3 read FPosition write FPosition;
      property Gain: Single read FGain write SetGain;
      property RolloffFactor: Single read FRolloffFactor write SetRolloff;
      property MaxDistance: Single read FMaxDistance write SetMaxDistance;
      property ReferenceDistance: Single read FReferenceDistance write SetReferenceDistance;
      property Pitch: Single read GetPitch write SetPitch;
      property GlobalEmitter: Boolean read FGlobalEmitter write FGlobalEmitter;
      property Active: Boolean read FActive write FActive;
      property TimeOffset64: TAuSamplestamp read FTimeOffset;
      property AutoFree: Boolean read FAutoFree write FAutoFree;

      property Properties: Byte read FProperties write FProperties;
  end;

  TAu3DStreamedEmitter = class(TAu3DCustomEmitter)
    protected
      function GetPitch: Single;override;
      procedure SetPitch(AValue: Single);override;
    public
      constructor Create(ASound: TAu3DStreamedSound);
      destructor Destroy;override;

      procedure Move(ATimeGap: Extended);override;
      function TimePosition64: TAuSamplestamp;override;
  end;

  TAu3DStaticEmitter = class(TAu3DCustomEmitter)
    private
      FTimePosition64: TAuSamplestamp;
      FPitch: Single;
      FStopProc: TAuNotifyEvent;

      procedure SetTimePosition64(AValue: TAuSamplestamp);
      procedure StopProc;
    protected
      function GetPitch: Single;override;
      procedure SetPitch(AValue: Single);override;
    public
      constructor Create(ASound: TAu3DStaticSound);
      destructor Destroy;override;

      procedure Move(ATimeGap: Extended);override;
      function TimePosition64: TAuSamplestamp;override;

      procedure SeekToSample(ASample: integer);
      procedure SeekToSecond(ASec: Single);

      property OnStop: TAuNotifyEvent read FStopProc write FStopProc;    
  end;


  TAu3DDistanceModel = (
    au3ddmInverseDistance,
    au3ddmInverseDistanceClamped,
    au3ddmLinearDistance,
    au3ddmLinearDistanceClamped,
    au3ddmNone
  );

  TAu3DSoundList = class(TList)
    private
      function GetItem(AIndex: integer): TAu3DCustomSound;
    protected
      procedure Notify(Ptr: Pointer; Action: TListNotification);override;
    public
      property Items[AIndex: integer]: TAu3DCustomSound read GetItem; default;
  end;

  TAu3DGainValues = array of Single;

  TAu3DEmitterProps = record
    Source: Pointer;
    GainValues: TAu3DGainValues;
    Position: TAuSamplestamp;
    Used: boolean;
    Tag: Pointer;
  end;
  PAu3DEmitterProps = ^TAu3DEmitterProps;

  TAu3DEmitterPropsList = class
    private
      FList: TList;
    public
      constructor Create;
      destructor Destroy;override;
      
      procedure BeginScene;
      procedure EndScene;
      procedure GetSourceObj(ASource: Pointer; var AProps: PAu3DEmitterProps);
  end;

  TAu3DEnvironment = class
    private
      FScale: Single;
      FSpeedOfSound: Single;
      FDistanceModel: TAu3DDistanceModel;
      procedure SetScale(AValue: Single);
      procedure SetSpeedOfSound(AValue: Single);
    public
      constructor Create;
      destructor Destroy;override;

      function DistanceGainFactor(ADist, AMax, ARolloff, AReference: Single): Single;

      property Scale: Single read FScale write SetScale;
      property SpeedOfSound: Single read FSpeedOfSound write SetSpeedOfSound;
      property DistanceModel: TAu3DDistanceModel read FDistanceModel write FDistanceModel;
  end;

  TAu3DListener = class;

  TAu3DListenerProc = procedure(AListener: TAu3DListener; ATimeGap: Double);

  TAu3DListener = class
    private
      FPosition: TAuVector3;
      FOrientation: TAuOrientation;
      FGain: Single;
      FSources: TAu3DEmitterPropsList;
      FProperties: Byte;
      FViewMatrix: TAcMatrix;
      FMoveProc: TAu3DListenerProc;
    public
      constructor Create;
      destructor Destroy;override;

      procedure Setup3DScene(const APos, ADir, AUp: TAcVector3);
      procedure SetupView(const AMat: TAcMatrix);

      procedure Move(ATimeGap: Double);

      property Position: TAuVector3 read FPosition write FPosition;
      property Orientation: TAuOrientation read FOrientation write FOrientation;
      property Gain: Single read FGain write FGain;
      property Sources: TAu3DEmitterPropsList read FSources;
      property Properites: Byte read FProperties write FProperties;
      property ViewMatrix: TAcMatrix read FViewMatrix;

      property OnMove: TAu3DListenerProc read FMoveProc write FMoveProc;
  end;

  TAu3DSoundRenderer = class
    private
      FSpeakerSetup: TAu3DSpeakerSetup;
      FFrequency: Cardinal;
      FSounds: TAu3DSoundList;
      FEnvironment: TAu3DEnvironment;
      FOutvalues: TAu3DGainValues;
      FGainvalues: TAu3DGainValues;
      FMutex: TAcMutex;
      FWroteData: boolean;
      function CalculateSoundAngle(APos: TAcVector4;
        var AAlpha: Single): Boolean;
      procedure CalculatePositionalSoundData(AListener: TAu3DListener;
        ASampleCount: integer; ABuf: PByte; AEmitter: TAu3DCustomEmitter; AClear: boolean;
        AObj: PAu3DEmitterProps);
      procedure CalculateStaticSoundData(AListener: TAu3DListener;
        ASampleCount: integer; ABuf: PByte; AEmitter: TAu3DCustomEmitter; AClear: boolean; AObj: PAu3DEmitterProps);
    public
      constructor Create(ASpeakerPreset: TAu3DSpeakerPreset;
        AFrequency: Cardinal);
      destructor Destroy;override;
      
      procedure Render(AListener: TAu3DListener; ASampleCount: integer;
        ABuf: PByte);

      procedure Lock;
      procedure Unlock;

      property Sounds: TAu3DSoundList read FSounds;
      property Setup: TAu3DSpeakerSetup read FSpeakerSetup;
      property Environment: TAu3DEnvironment read FEnvironment;
      property Frequency: Cardinal read FFrequency;
  end;                                             
  

implementation

//Helper functions

function LinInt(av1, av2, ap: Single): Single;inline;
begin
  result := av1 * (1 - ap) + av2 * ap;
end;

function LinIntExt(av1, av2: Extended; ap: Single): Extended;inline;
begin
  result := av1 * (1 - ap) + av2 * ap;
end;

function PositiveAngle(aa: single): single;
begin
  result := aa;
  while result < 0 do
    result := result + 2 * PI;
end;

function AngleBetween(a1, a2: single): single;
begin
  result := abs(PositiveAngle(a1) - PositiveAngle(a2));
  if result > PI then
    result := result - PI;
end;

function NormAngle(aa: single): single;
begin
  result := aa;
  if result > 0 then
    while result > PI do
      result := result - 2 * PI
  else
    while result < -PI do
      result := result + 2 * PI;
end;

type
  TExtVec2 = record
    x, y: Extended;
  end;

function SolveMat(v1, v2, x: TExtVec2): TExtVec2;
var
  deta: Extended;
begin
  //By default return zero
  result.x := 0; result.y := 0;

  deta := v1.x * v2.y - v1.y * v2.x;
  if not IsZero(deta) then
  begin
    result.x := (x.x * v2.y - x.y * v2.x) / deta;
    result.y := (v1.x * x.y - v1.y * x.x) / deta;
  end;
end;

function Norm(v: TExtVec2): TExtVec2;
var
  l: Extended;
begin
  l := Sqrt(Sqr(v.x) + Sqr(v.y));
  if l > 0 then
  begin
    v.x := v.x / l;
    v.y := v.y / l;
  end;

  result := v;
end;

{ TAu3DSoundRenderer }

constructor TAu3DSoundRenderer.Create(ASpeakerPreset: TAu3DSpeakerPreset;
  AFrequency: Cardinal);
begin
  inherited Create;

  //Create the mutex used in the lock and unlock function.
  FMutex := TAcMutex.Create;

  FEnvironment := TAu3DEnvironment.Create;
  FSpeakerSetup := TAu3DSpeakerSetup.Create(ASpeakerPreset);
  FSounds := TAu3DSoundList.Create;
  FFrequency := AFrequency;


  SetLength(FOutvalues, FSpeakerSetup.ChannelCount);
  SetLength(FGainvalues, FSpeakerSetup.ChannelCount);
end;

destructor TAu3DSoundRenderer.Destroy;
begin
  FSounds.Free;
  FSpeakerSetup.Free;
  Environment.Free;

  //Free the mutex
  FMutex.Free;
  inherited;
end;

procedure TAu3DSoundRenderer.Lock;
begin
  FMutex.Acquire;
end;

procedure TAu3DSoundRenderer.Unlock;
begin
  FMutex.Release;
end;

procedure TAu3DSoundRenderer.Render(AListener: TAu3DListener;
  ASampleCount: integer; ABuf: PByte);
var
  i, j: integer;
  pobj: PAu3DEmitterProps;
begin
  FWroteData := false;

  //Exit in invalid sample count values
  if (ASampleCount <= 0) or (ABuf = nil) or (AListener = nil) then
    exit;
    
  Lock;
  try
    AListener.Sources.BeginScene;

    AListener.Move(ASampleCount / Frequency);

    for i := 0 to FSounds.Count - 1 do
    begin
      if FSounds[i].Active then
      begin
        FSounds[i].Move(ASampleCount / FFrequency);

        for j := 0 to FSounds[i].Emitters.Count - 1 do
        begin
          if FSounds[i].Emitters[j].Active then
          begin
            //Get the listener information attached to the sound
            AListener.Sources.GetSourceObj(FSounds[i].Emitters[j], pobj);

            FSounds[i].Emitters[j].Move(ASampleCount / FFrequency);

            //Do the actual rendering
            if not FSounds[i].Emitters[j].GlobalEmitter then
              CalculatePositionalSoundData(AListener, ASampleCount, ABuf,
                FSounds[i].Emitters[j], not FWroteData, pobj)
            else
              CalculateStaticSoundData(AListener, ASampleCount, ABuf,
                FSounds[i].Emitters[j], not FWroteData, pobj);
          end;
        end;
      end;
    end;

    //If no emitter has written any data, zero the buffer memory
    if not FWroteData then
      FillChar(ABuf^, FSpeakerSetup.OutputChannelCount * SizeOf(Single) *
        ASampleCount, 0);

    AListener.Sources.EndScene;
  finally
    Unlock;
  end;
end;             

function TAu3DSoundRenderer.CalculateSoundAngle(APos: TAcVector4;
  var AAlpha: Single): boolean;
var
  l: Double;
begin
  result := false;
  
  l := Sqrt(Sqr(APos.x) + Sqr(APos.y));
  if not IsZero(l) then
  begin
    AAlpha := ArcCos(APos.x / l);
    if APos.y < 0 then
      AAlpha := 2 * PI - AAlpha;
    result := true;
  end;
end;

procedure TAu3DSoundRenderer.CalculateStaticSoundData(AListener: TAu3DListener;
  ASampleCount: integer; ABuf: PByte; AEmitter: TAu3DCustomEmitter;
  AClear: boolean; AObj: PAu3DEmitterProps);
var
  j, k: integer;
  ip: Single;
  gain: Single;
  pos: Int64;
  posadd: Int64;
  props: Byte;
  outvals: TAu3DGainValues;
  ps: PSingle;
begin
  ps := PSingle(ABuf);
  SetLength(outvals, AEmitter.Sound.Parameters.Channels);
  
  props := AEmitter.Properties and AListener.Properites;

  //Initialize the channel mapper
  if AEmitter.Sound.Mapper.OutCount = 0 then
    AEmitter.Sound.Mapper.BuildMatrix(
      AEmitter.Sound.Parameters.Channels,
      FSpeakerSetup.OutputChannelCount);

  if props and AU3DPROP_GAIN > 0 then
    gain := AEmitter.Gain * AListener.Gain
  else
    gain := 1;

  if not Assigned(AObj^.GainValues) then
  begin
    SetLength(AObj^.GainValues, 1);
    AObj^.GainValues[0] := gain;
  end;

  posadd := (AEmitter.TimePosition64 - AObj^.Position) div ASampleCount;
  pos := AObj^.Position - AEmitter.TimeOffset64;

  FWroteData := true;

  for j := 0 to ASampleCount - 1 do
  begin
    ip := j / ASampleCount;

    //Read a sample from the sound buffer
    for k := 0 to AEmitter.Sound.Parameters.Channels - 1 do
      outvals[k] := AEmitter.Sound.Ring.GetSample(pos, k) *
        LinInt(AObj^.GainValues[0], gain, ip);

    AEmitter.Sound.Mapper.Map(@outvals[0], PSingle(ps), AClear);

    pos := pos + posadd;
  end;

  AObj^.GainValues[0] := gain;
  AObj^.Position := AEmitter.TimePosition64;
end;

procedure TAu3DSoundRenderer.CalculatePositionalSoundData(
  AListener: TAu3DListener; ASampleCount: integer; ABuf: PByte;
  AEmitter: TAu3DCustomEmitter; AClear: boolean; AObj: PAu3DEmitterProps);
var
  dist: Single;
  smpl: Single;
  gain: Single;
  hasalpha: Boolean;
  alpha: Single;
  pos, posd: Int64;
  posadd: Int64;
  k, j: integer;
  ip: Single;
  ps: PByte;
  props: Byte;
  pos4: TAcVector4;
begin
  ps := ABuf;

  props := AEmitter.Properties and AListener.Properites;
  dist := 0;

  //Get the position vector
  pos4 := AcMatrix_Multiply_Vector(AListener.ViewMatrix,
    AcVector4(AEmitter.Position, 1));

  //Calculate the distance towards the listener
  if (props and (AU3DPROP_PHASE or AU3DPROP_GAIN) > 0) then
  begin
    //Calculate the distance
    dist := Sqrt(
      Sqr(pos4.x) +
      Sqr(pos4.y) +
      Sqr(pos4.z));
  end;

  //Calculate the gain values
  if props and AU3DPROP_GAIN > 0 then
  begin
    gain := AEmitter.Gain * AListener.Gain *
      FEnvironment.DistanceGainFactor(
        dist * FEnvironment.Scale, AEmitter.MaxDistance, AEmitter.RolloffFactor,
        AEmitter.ReferenceDistance);
    hasalpha := CalculateSoundAngle(pos4, alpha);
  end else
  begin
    gain := 1;
    hasalpha := false;
  end;

  //Read the channel factors
  for k := 0 to FSpeakerSetup.ChannelCount - 1 do
    if hasalpha then
      FGainvalues[k] := FSpeakerSetup.MultFac(k, alpha) * gain
    else
      FGainvalues[k] := gain;

  if not Assigned(AObj^.GainValues) then
    AObj^.GainValues := Copy(FGainvalues);

  //Phase/Dopplereffect/Time calculation
  if props and AU3DPROP_PHASE > 0 then
    posd := AEmitter.TimePosition64 -
      round((dist * FEnvironment.Scale) / FEnvironment.SpeedOfSound
        * AEmitter.Sound.Parameters.Frequency * (1 shl 16))
  else
    posd := AEmitter.TimePosition64;

  FWroteData := true;

  posadd := (posd - AObj^.Position) div ASampleCount;
  pos := AObj^.Position - AEmitter.TimeOffset64;
  for j := 0 to ASampleCount - 1 do
  begin
    ip := j / ASampleCount;

    //Read a sample from the sound buffer
    smpl := AEmitter.Sound.Ring.GetSample(pos, 0);

    //Calculate the current sample value and write it to the output buffer
    for k := 0 to FSpeakerSetup.ChannelCount - 1 do
      //Mix the new sample value with the old buffer content
      FOutvalues[k] :=
        LinInt(AObj^.GainValues[k], FGainvalues[k], ip) * smpl;

    FSpeakerSetup.Mapper.Map(@FOutvalues[0], PSingle(ps), AClear);

    pos := pos + posadd;
  end;

  for k := 0 to FSpeakerSetup.ChannelCount - 1 do
    AObj^.GainValues[k] := FGainvalues[k];
  AObj^.Position := posd;
end;

{ TAu3DSpeakerSetup }

constructor TAu3DSpeakerSetup.Create(ASpeakerPreset: TAu3DSpeakerPreset);
begin
  inherited Create;

  FMapper := TAu3DChannelMapper.Create();
  FSpeakerPreset := ASpeakerPreset;
  LoadPreset(ASpeakerPreset);

  FTableSize := 4 * 360;
  SetLength(FSpeakerFactors, FChannelCount);
  CalcFacTable(FTableSize);
end;

destructor TAu3DSpeakerSetup.Destroy;
begin
  FMapper.Free;
  inherited;
end;

procedure TAu3DSpeakerSetup.LoadPreset(APreset: TAu3DSpeakerPreset);
begin
  case FSpeakerPreset of
    au3dssMono, au3dssStereo, au3dssQuadraphonic:
    begin
      FChannelCount := 4;
      SetLength(FSpeakers, FChannelCount);
      FSpeakers[0].angle := -135 * PI / 180;
      FSpeakers[0].speaker := au3dspSideLeft;
      FSpeakers[1].angle :=  -45 * PI / 180;
      FSpeakers[1].speaker := au3dspFrontLeft;
      FSpeakers[2].angle :=   45 * PI / 180;
      FSpeakers[2].speaker := au3dspFrontRight;
      FSpeakers[3].angle :=  135 * PI / 180;
      FSpeakers[3].speaker := au3dspSideRight;
    end;

    au3dss51:
    begin
      FChannelCount := 5;
      SetLength(FSpeakers, FChannelCount);
      FSpeakers[0].angle := -110 * PI / 180;
      FSpeakers[0].speaker := au3dspSideLeft;
      FSpeakers[1].angle :=  -30 * PI / 180;
      FSpeakers[1].speaker := au3dspFrontLeft;
      FSpeakers[2].angle :=    0 * PI / 180;
      FSpeakers[2].speaker := au3dspCenter;
      FSpeakers[3].angle :=   30 * PI / 180;
      FSpeakers[3].speaker := au3dspFrontRight;
      FSpeakers[4].angle :=  110 * PI / 180;
      FSpeakers[4].speaker := au3dspSideRight;
    end;

    au3dss71:
    begin
      FChannelCount := 7;
      SetLength(FSpeakers, FChannelCount);
      FSpeakers[0].angle := -150  * PI / 180;
      FSpeakers[0].speaker := au3dspRearLeft;
      FSpeakers[1].angle :=  -90  * PI / 180;
      FSpeakers[1].speaker := au3dspSideLeft;
      FSpeakers[2].angle :=  -30  * PI / 180;
      FSpeakers[2].speaker := au3dspFrontLeft;
      FSpeakers[3].angle :=    0  * PI / 180;
      FSpeakers[3].speaker := au3dspCenter;
      FSpeakers[4].angle :=   30  * PI / 180;
      FSpeakers[4].speaker := au3dspFrontRight;
      FSpeakers[5].angle :=   90  * PI / 180;
      FSpeakers[5].speaker := au3dspSideRight;
      FSpeakers[6].angle :=  150  * PI / 180;
      FSpeakers[6].speaker := au3dspRearRight;
    end;
  end;

  FOutputChannelCount := Ord(FSpeakerPreset);       
  FMapper.BuildMatrix(FSpeakers, FOutputChannelCount);
end;

procedure TAu3DSpeakerSetup.CalcFacTable(ACount: integer);
var
  v1, r1: TExtVec2;
  l1, l2: TExtVec2;
  step, sum: Double;
  i, j: Integer;
  s1, s2: Integer;
begin
  for i := 0 to FChannelCount - 1 do
    SetLength(FSpeakerFactors[i], ACount);

  //Zero all values
  for i := 0 to FChannelCount - 1 do
    for j := 0 to ACount - 1 do
      FSpeakerFactors[i][j] := 0;

  step := 2 * PI / ACount;
  for i := 0 to ACount - 1 do
  begin
    //Calculate the sound vector
    SinCos(i * step + PI/2, v1.y, v1.x);

    for j := 0 to FChannelCount - 1 do
    begin
      //Calculate the two speakers to select for base translation
      s1 := j;
      s2 := (j + 1) mod FChannelCount;

      //Obtain the speaker 1 vector
      SinCos(FSpeakers[s1].angle, l1.y, l1.x);

      //Obtain the speaker 2 vector
      SinCos(FSpeakers[s2].angle, l2.y, l2.x);

      //Treat l1 and l2 as a new vector room basis and translate v1 to this
      //vector room.
      //      / r \
      //v1' = |   |  = r1
      //      \ s /
      //
      //l1 * r + l2 * s = v1

      r1 := SolveMat(l1, l2, v1);

      //Normalize the output vector
      r1 := Norm(r1);

      if r1.x > 0 then
        FSpeakerFactors[s1][i] := FSpeakerFactors[s1][i] + r1.x;

      if r1.y > 0 then
        FSpeakerFactors[s2][i] := FSpeakerFactors[s2][i] + r1.y;
    end;
  end;

  //Normalize the output values
  for i := 0 to ACount - 1 do
  begin
    sum := 0;
    for j := 0 to FChannelCount - 1 do
      sum := sum + FSpeakerFactors[j][i];
    sum := 1 / sum;
    for j := 0 to FChannelCount - 1 do
      FSpeakerFactors[j][i] := FSpeakerFactors[j][i] * sum;
  end;
end;

function TAu3DSpeakerSetup.MultFac(AChannel: integer; AAngle: Single): Single;
begin
  result := FSpeakerFactors[AChannel][round(FTableSize * (AAngle / (2 * PI)))];
end;

{ TAu3DSoundList }

function TAu3DSoundList.GetItem(AIndex: integer): TAu3DCustomSound;
begin
  result := inherited Items[AIndex];
end;

procedure TAu3DSoundList.Notify(Ptr: Pointer; Action: TListNotification);
begin
  if (Action = lnDeleted) and TAu3DCustomSound(Ptr).AutoFree then
    TAu3DCustomSound(Ptr).Free;
end;

{ TAu3DChannelMapper }

constructor TAu3DChannelMapper.Create;
begin
  inherited Create;

  FOutCount := 0;

  //Write the channel output configuration mask according to ANSI/CEA-863-A,
  //see http://en.wikipedia.org/wiki/Surround_sound#Channel_identification
  SetLength(FChannelLayout, 8);
  FChannelLayout[0] := au3dspFrontLeft;
  FChannelLayout[1] := au3dspFrontRight;
  FChannelLayout[2] := au3dspCenter;
  FChannelLayout[3] := au3dspSubwoofer;
  FChannelLayout[4] := au3dspSideLeft;
  FChannelLayout[5] := au3dspSideRight;
  FChannelLayout[6] := au3dspRearLeft;
  FChannelLayout[7] := au3dspRearRight;
end;

type
  TIntegerArray = array of Integer;

procedure TAu3DChannelMapper.IntBuildMatrix;

  //Function used to map a virtual input speaker (AIn) to the real output speakers (ARes).
  //The array ARes contains the actual real stream identification numbers
  //This function is used if there are less or equal virtual input speakers than
  //output speakers
  procedure GetOutputSpeaker1(AIn: TAu3DSpeaker; var ARes: TIntegerArray);
  var
    i: integer;
    best: Integer;
    delta: Integer;
  begin
    best := 0;

    //Determine the best distance value
    for i := 0 to High(FSpeakerSettings) do
    begin
      delta := Abs(Ord(AIn) - Ord(FSpeakerSettings[i].speaker));
      if (i = 0) or (delta < best) then
        best := delta;
    end;

    //Add all speakers with this distance value to the output array
    SetLength(ARes, 0);
    for i := 0 to High(FSpeakerSettings) do
    begin
      delta := Abs(Ord(AIn) - Ord(FSpeakerSettings[i].speaker));
      if delta = best then
      begin
        SetLength(ARes, Length(ARes) + 1);
        ARes[High(ARes)] := i;
      end;
    end;
  end;

  //Function used to map a virtual input speaker (AIn) to the real output speakers (ARes).
  //The array ARes contains the actual real stream identification numbers
  //This function is used if there are more virtual input speakers than
  //output speakers
  procedure GetOutputSpeaker2(AIn: TAu3DSpeaker; var ARes: TIntegerArray);
  var
    i: integer;
    best: Integer;
    delta : Integer;
  begin
    best := trunc(Length(FSpeakerSettings) / FOutCount);

    //Determine the best speakers
    SetLength(ARes, 0);
    for i := 0 to High(FSpeakerSettings) do
    begin
      delta := Abs(Ord(AIn) - Ord(FSpeakerSettings[i].speaker));
      if (delta < best) then
      begin
        SetLength(ARes, Length(ARes) + 1);
        ARes[High(ARes)] := i;
      end;
    end;
  end;

var
  i, j: integer;
  res: TIntegerArray;
begin
  //Create and initialize the channel matrix
  SetLength(FChannelMatrix, FOutCount, Length(FSpeakerSettings));
  for i := 0 to FOutCount - 1 do
    for j := 0 to High(FSpeakerSettings) do
      FChannelMatrix[i][j] := 0;

  //Pick every output speaker
  for i := 0 to FOutCount - 1 do
  begin
    //If the output speaker isn't a subwoofer...
    if (FChannelLayout[i] <> au3dspSubwoofer) then
    begin
      //...pick all input channels which contribute to the selected output speaker
      if FOutCount >= Length(FSpeakerSettings) then
        GetOutputSpeaker1(FChannelLayout[i], res)
      else
        GetOutputSpeaker2(FChannelLayout[i], res);

      //and set this value in the channel matrix
      for j := 0 to High(res) do
        FChannelMatrix[i][res[j]] := 1 / Length(res);
        //FChannelMatrix[i][res[j]] := 1;
    end else
      //Every input channel contributes to the subwoofer output channel -
      //a low pass filter will be applied lateron
      for j := 0 to High(FSpeakerSettings) do
        //Setting this to one should be correct, as the sum of all channels is
        //normalized to one
        FChannelMatrix[i][j] := 1;
  end;  
end;

procedure TAu3DChannelMapper.BuildMatrix(ASettings: TAu3DSpeakerSettings;
  AOutCount: integer);  
begin
  FSpeakerSettings := Copy(ASettings);
  FOutCount := AOutCount;

  IntBuildMatrix;
end;

procedure TAu3DChannelMapper.BuildMatrix(AInCount, AOutCount: integer);
var
  i: integer;
begin
  FOutCount := AOutCount;

  //Initialize the speakers settings vector manually
  SetLength(FSpeakerSettings, AInCount);
  for i := 0 to AInCount - 1 do
  begin
    FSpeakerSettings[i].speaker := FChannelLayout[i];
    FSpeakerSettings[i].angle := 0; //actually "angle" is not used in this class
  end;

  IntBuildMatrix;
end;

procedure TAu3DChannelMapper.Map(AIn: PSingle; var AOut: PSingle; AClear: boolean);
var
  i, j: integer;
  psin: PSingle;
begin
  for i := 0 to FOutCount - 1 do
  begin
    if AClear then
      AOut^ := 0;

    psin := AIn;
    for j := 0 to Length(FSpeakerSettings) - 1 do
    begin
      AOut^ := AOut^ + psin^ * FChannelMatrix[i][j];
      inc(psin);
    end;
    inc(AOut);
  end;
end;

destructor TAu3DChannelMapper.Destroy;
begin

  inherited;
end;

{ TAu3DSoundSourcePropsList }

constructor TAu3DEmitterPropsList.Create;
begin
  inherited Create;

  FList := TList.Create;
end;

destructor TAu3DEmitterPropsList.Destroy;
var
  pobj: PAu3DEmitterProps;
  i: integer;
begin
  for i := FList.Count - 1 downto 0 do
  begin
    pobj := FList[i];
    Dispose(pobj);
    FList.Delete(i);
  end;
  
  FList.Free;
  inherited;
end;

procedure TAu3DEmitterPropsList.BeginScene;
var
  i: integer;
begin
  for i := 0 to FList.Count - 1 do
    PAu3DEmitterProps(FList[i])^.Used := false;
end;

procedure TAu3DEmitterPropsList.EndScene;
var
  pobj: PAu3DEmitterProps;
  i: integer;
begin
  for i := FList.Count - 1 downto 0 do
  begin
    pobj := FList[i];

    //Reset the manual position change value
    TAu3DCustomEmitter(pobj^.Source).FManualPositionChange := false;

    if not pobj^.Used then
    begin
      Dispose(pobj);
      FList.Delete(i);
    end;
  end;
end;

procedure TAu3DEmitterPropsList.GetSourceObj(ASource: Pointer;
  var AProps: PAu3DEmitterProps);
var
  pobj: PAu3DEmitterProps;
  i: integer;
begin
  AProps := nil;

  for i := 0 to FList.Count - 1 do
  begin
    pobj := FList[i];
    if pobj^.Source = ASource then
    begin
      AProps := pobj;
      pobj^.Used := true;
      break;
    end;
  end;

  //Remove the emitter object from the list if the position has been changed
  //manually.
  if TAu3DCustomEmitter(ASource).FManualPositionChange and (AProps <> nil) then
  begin
    FList.Remove(AProps);
    AProps := nil;
  end;

  if (AProps = nil) then
  begin
    New(pobj);
    pobj^.Source := ASource;
    pobj^.Used := true;
    pobj^.Position := TAu3DCustomEmitter(ASource).TimePosition64;
    FList.Add(pobj);
    AProps := pobj;
  end;
end;

{ TAu3DSoundListener }

constructor TAu3DListener.Create;
begin
  inherited Create;

  FSources := TAu3DEmitterPropsList.Create;
  FGain := 1;
  FProperties := AU3DPROP_ALL;
  FViewMatrix := AcMatrix_Identity;
end;

destructor TAu3DListener.Destroy;
begin
  FSources.Free;
  inherited;
end;

procedure TAu3DListener.Move(ATimeGap: Double);
begin
  if Assigned(FMoveProc) then
    FMoveProc(self, ATimeGap);
end;

procedure TAu3DListener.Setup3DScene(const APos, ADir, AUp: TAcVector3);
begin
  FViewMatrix := AcMatrix_View_LookAt(APos, ADir, AUp);
end;

procedure TAu3DListener.SetupView(const AMat: TAcMatrix);
begin
  FViewMatrix := AMat;
end;

{ TAu3DEnvironment }

constructor TAu3DEnvironment.Create;
begin
  inherited Create;

  FScale := 1;
  FSpeedOfSound := 343.3;
  FDistanceModel := au3ddmInverseDistanceClamped;
end;

destructor TAu3DEnvironment.Destroy;
begin

  inherited;
end;

//see http://wiki.delphigl.com/index.php/alDistanceModel for mor details
function TAu3DEnvironment.DistanceGainFactor(ADist, AMax, ARolloff,
  AReference: Single): Single;
var
  divisor: Single;
begin
  result := 1.0;
  
  case FDistanceModel of
    au3ddmInverseDistance:
    begin
      //The divisor must not get zero
      divisor := (AReference + ARolloff * (ADist - AReference));
      if divisor < 0.00001 then
        divisor := 0.00001;

      result := AReference / divisor;
    end;

    au3ddmInverseDistanceClamped:
    begin
      if ADist < AReference then
        ADist := AReference;
      if ADist > AMax then
        ADist := AMax;

      result := AReference / (AReference + ARolloff * (ADist - AReference));
    end;

    au3ddmLinearDistance:
    begin
      if ADist > AMax then
        ADist := AMax;

      result := (1 - ARolloff * (ADist - AReference) / (AMax - AReference));
    end;

    au3ddmLinearDistanceClamped:
    begin
      if ADist < AReference then
        ADist := AReference;
      if ADist > AMax then
        ADist := AMax;

      result := (1 - ARolloff * (ADist - AReference) / (AMax - AReference));
    end;
  end;
end;

procedure TAu3DEnvironment.SetScale(AValue: Single);
begin
  if AValue > 0 then
    FScale := AValue;
end;

procedure TAu3DEnvironment.SetSpeedOfSound(AValue: Single);
begin
  if AValue > 0 then
    FSpeedOfSound := AValue;
end;

{ TAu3DEmitterList }

function TAu3DEmitterList.GetItem(AIndex: integer): TAu3DCustomEmitter;
begin
  result := inherited Items[AIndex];
end;

procedure TAu3DEmitterList.Notify(ptr: Pointer; action: TListNotification);
begin
  if (action = lnDeleted) and (TAu3DCustomEmitter(ptr).AutoFree)then
   TAu3DCustomEmitter(ptr).Free;
end;

{ TAu3DCustomSound }

constructor TAu3DCustomSound.Create(AParameters: TAuAudioParameters;
  ASamples: Integer);
begin
  inherited Create;

  //Copy the AParameters parameter
  FParameters := AParameters;
  FBufferSamples := ASamples;

  //Preset FAutoFree and FActive to true
  FAutoFree := true;
  FActive := true;

  //Create the emitter list and setup the channel mapper
  FEmitters := TAu3DEmitterList.Create;
  FMapper := TAu3DChannelMapper.Create;
  FRing := TAu3DAudioRingBuffer.Create(FBufferSamples, AParameters.Channels);
end;

destructor TAu3DCustomSound.Destroy;
begin
  if FRing <> nil then
    FRing.Free;
  FRing := nil;

  if FMapper <> nil then
    FMapper.Free;
  FMapper := nil;

  if FEmitters <> nil then
    FEmitters.Free;
  FEmitters := nil;

  inherited;
end;

procedure TAu3DCustomSound.ClearBuffers;
begin
  FRing.Clear;
end;

{ TAu3DStreamedSound }

constructor TAu3DStreamedSound.Create(ACallback: TAuReadCallback;
  const AParameters: TAuAudioParameters; ABufferTime: Single);
begin
  //Create the ring buffer with the desired size
  inherited Create(AParameters, Trunc(ABufferTime * AParameters.Frequency));

  FCallback := ACallback;
  FPitch := 1.0;
  FBuf := nil;
  FBufSize := 0;
end;

destructor TAu3DStreamedSound.Destroy;
begin
  //Free the buffer memory
  if FBuf <> nil then
    FreeMem(FBuf, FBufSize);
  FBuf := nil;
  
  inherited;
end;

procedure TAu3DStreamedSound.Move(ATimeGap: Extended);
var
  c: Cardinal;
begin
  //Check whether new samples have to be read into the sound buffer
  if (Ring.Filled < Ring.Size) or
    ((Ring.SmplPos - FTimePosition64 div (1 shl 16)) <
      Ring.SmplSize / 2) then
  begin
    //Calculate the count of samples which have to be read into the ring buffer
    c := round(ATimeGap * Parameters.Frequency * FPitch * 2);
    ReadSamples(c);
  end;

  //Advance the sound position
  FTimePosition64 := FTimePosition64 +
    round((ATimeGap * FPitch * Parameters.Frequency * (1 shl 16)));
end;

procedure TAu3DStreamedSound.ClearBuffers;
begin
  inherited;

  FTimePosition64 := 0;  
end;

procedure TAu3DStreamedSound.ReadSamples(ACount: Cardinal);
var
  size: Cardinal;
  sd: TAuSyncData;
  smpls: Integer;
begin
  //Reserve some buffer memory
  size := AuBytesPerSample(FParameters) * ACount;
  if (size <> FBufSize) or (FBuf = nil) then
    ReallocMem(FBuf, size);
  FBufSize := size;

  //Read the samples and write them into the ringbuffer
  smpls := FCallback(FBuf, size, sd) div AuBytesPerSample(FParameters);
  FRing.WriteSamples(smpls, PSingle(FBuf));
end;

procedure TAu3DStreamedSound.SetPitch(AValue: Single);
begin
  if AValue > 0 then
    FPitch := AValue;
end;

{ TAu3DStaticSound }

constructor TAu3DStaticSound.Create(ABuf: PByte; ASamples: Cardinal;
  const AParameters: TAuAudioParameters);
begin
  inherited Create(AParameters, ASamples);

  //Write the memory into the ringbuffer
  FRing.WriteSamples(ASamples, PSingle(ABuf));
end;

destructor TAu3DStaticSound.Destroy;
begin
  inherited;
end;

procedure TAu3DStaticSound.Move(ATimeGap: Extended);
begin
  //Do nothing here.
end;

procedure TAu3DStaticSound.SetLoop(AValue: Boolean);
begin
  FLoop := AValue;
  Ring.Loop := AValue;
end;

procedure TAu3DStaticSound.ClearBuffers;
var
  i: integer;
begin
  inherited;

  for i := 0 to Emitters.Count - 1 do
    TAu3DStaticEmitter(Emitters[i]).SeekToSample(0);
end;


{ TAu3DCustomEmitter }

constructor TAu3DCustomEmitter.Create(ASound: TAu3DCustomSound);
begin
  inherited Create;

  FSound := ASound;
  
  if ASound = nil then; //! RAISE EXCEPTION          

  //Preset some parameters
  FGain := 1.0;
  FGlobalEmitter := false;
  FAutoFree := true;
  FPosition := AcVector3(0, 0, 0);
  FReferenceDistance := 1;
  FRolloffFactor := 1;
  FMaxDistance := 10000;
  FProperties := AU3DPROP_ALL;
  FActive := true;
  FTimeoffset := 0;

  //Add this emitter to the sound's emitter list.
  FSound.Emitters.Add(self)
end;

destructor TAu3DCustomEmitter.Destroy;
begin
  //Prevent the emitter list from freeing this instance while removing it from
  //the list.  
  FAutoFree := false;
  FSound.Emitters.Remove(self);

  inherited;
end;

procedure TAu3DCustomEmitter.SetGain(AValue: Single);
begin
  if AValue >= 0 then
    FGain := AValue;
end;

procedure TAu3DCustomEmitter.SetMaxDistance(AValue: Single);
begin
  if AValue > 0 then
    FMaxDistance := AValue;
end;

procedure TAu3DCustomEmitter.SetReferenceDistance(AValue: Single);
begin
  if AValue > 0 then
    FReferenceDistance := AValue;
end;

procedure TAu3DCustomEmitter.SetRolloff(AValue: Single);
begin
  if AValue > 0 then
    FRolloffFactor := AValue;
end;

function TAu3DCustomEmitter.TellSample: Integer;
begin
  result := TimePosition64 div (1 shl 16);
end;

function TAu3DCustomEmitter.TellSecond: Single;
begin
  result := (TimePosition64 div (1 shl 16)) / Sound.Parameters.Frequency;
end;

{ TAu3DStreamedEmitter }

constructor TAu3DStreamedEmitter.Create(ASound: TAu3DStreamedSound);
begin
  inherited Create(ASound);
end;

destructor TAu3DStreamedEmitter.Destroy;
begin
  inherited;
end;

function TAu3DStreamedEmitter.GetPitch: Single;
begin
  result := TAu3DStreamedSound(Sound).Pitch;
end;

procedure TAu3DStreamedEmitter.Move(ATimeGap: Extended);
begin
  //Do nothing.
end;

procedure TAu3DStreamedEmitter.SetPitch(AValue: Single);
begin
  TAu3DStreamedSound(Sound).Pitch := AValue;
end;

function TAu3DStreamedEmitter.TimePosition64: TAuSamplestamp;
begin
  result := TAu3DStreamedSound(Sound).FTimePosition64;
end;

{ TAu3DStaticEmitter }

constructor TAu3DStaticEmitter.Create(ASound: TAu3DStaticSound);
begin
  inherited Create(ASound);

  //Preset the pitch value
  FPitch := 1.0;
end;

destructor TAu3DStaticEmitter.Destroy;
begin
  AuQueueRemove(self);

  inherited;
end;

procedure TAu3DStaticEmitter.Move(ATimeGap: Extended);
begin
  //If the sound is not stream, each emitter is reponsible for it's own
  //position time stamp.
  FTimePosition64 := FTimePosition64 +
    round((ATimeGap * FPitch * Sound.Parameters.Frequency * (1 shl 16)));

  //Handle overflow
  if ((FTimePosition64 - FTimeOffset) div (1 shl 16)) >= Sound.BufferSamples then
  begin
    if Assigned(FStopProc) then
      AuQueueCall(StopProc);

    if TAu3DStaticSound(FSound).Loop then
      while ((FTimePosition64 - FTimeOffset) div (1 shl 16) >= Sound.BufferSamples) do
        FTimeOffset := FTimeOffset + Int64(Sound.BufferSamples) * (1 shl 16);
  end;
end;

procedure TAu3DStaticEmitter.SeekToSample(ASample: integer);
begin
  SetTimePosition64(Int64(ASample shl 16));
end;

procedure TAu3DStaticEmitter.SeekToSecond(ASec: Single);
begin
  SetTimePosition64(round(ASec * Sound.Parameters.Frequency) * (1 shl 16));
end;

procedure TAu3DStaticEmitter.SetTimePosition64(AValue: TAuSamplestamp);
begin
  FManualPositionChange := true;
  FTimePosition64 := AValue;
  FTimeOffset := 0;
end;

procedure TAu3DStaticEmitter.StopProc;
begin
  if Assigned(FStopProc) then
    FStopProc(self);
end;

function TAu3DStaticEmitter.TimePosition64: TAuSamplestamp;
begin
  result := FTimePosition64;
end;

function TAu3DStaticEmitter.GetPitch: Single;
begin
  result := FPitch;
end;

procedure TAu3DStaticEmitter.SetPitch(AValue: Single);
begin
  if AValue > 0 then
    FPitch := AValue;
end;

end.