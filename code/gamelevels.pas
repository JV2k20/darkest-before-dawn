{
  Copyright 2013 Michalis Kamburelis.

  This file is part of "Darkest Before Dawn".

  "Darkest Before Dawn" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Darkest Before Dawn" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Level-specific logic. }
unit GameLevels;

interface

uses Classes, CastleLevels, Castle3D, CastleScene, DOM, FGL, CastleShapes,
  CastleVectors, X3DNodes, CastleBoxes;

type
  TLevel1 = class(TLevelLogic)
  strict private
  type
    TElevator = class
    strict private
      Moving: T3DLinearMoving;
      Scene: TCastleScene;
    public
      constructor Create(const Name: string; const World: T3DWorld;
        const Owner: TLevel1; const Height: Single);
      procedure Update;
    end;

    TElevatorList = specialize TFPGObjectList<TElevator>;
  var
    Elevators: TElevatorList;
    Lights: TVector3SingleList;
    BrightnessEffect, BackgroundEffect: TEffectNode;
    MorningEmpty, MorningFull: TVector3Single;
    GameWinBox: TBox3D;
  public
    constructor Create(AOwner: TComponent; AWorld: T3DWorld;
      MainScene: TCastleScene; DOMElement: TDOMElement); override;
    destructor Destroy; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;
    function Placeholder(const Shape: TShape;
      const PlaceholderName: string): boolean; override;
  end;

implementation

uses SysUtils, CastleFilesUtils, Game, CastleStringUtils, CastleWarnings,
  X3DFields, CastleUtils;

{ TLevel1.TElevator ---------------------------------------------------------- }

constructor TLevel1.TElevator.Create(const Name: string; const World: T3DWorld;
  const Owner: TLevel1; const Height: Single);
begin
  inherited Create;

  Scene := Owner.LoadLevelScene(ApplicationData('level/1/' + Name), true);

  Moving := T3DLinearMoving.Create(Owner);
  Moving.Add(Scene);
  Moving.MoveTime := Height / 3.0;
  Moving.TranslationEnd := Vector3Single(0, Height, 0);
  World.Add(Moving);
end;

procedure TLevel1.TElevator.Update;
var
  PlayerInside: boolean;
begin
  PlayerInside := Scene.BoundingBox.PointInside2D(Player.Position, 1);
  if Moving.CompletelyBeginPosition and PlayerInside then
  begin
    Moving.GoEndPosition;
  end else
  if Moving.CompletelyEndPosition and not PlayerInside then
  begin
    Moving.GoBeginPosition;
  end else
  if PlayerInside and
     (not Moving.CompletelyEndPosition) and
     (not Moving.CompletelyBeginPosition) then
    GoingUp := true;
end;

{ TLevel1 -------------------------------------------------------------------- }

const
  DistanceFactorUniform = 'distance_factor';
  MorningUniform = 'morning';

constructor TLevel1.Create(AOwner: TComponent; AWorld: T3DWorld;
  MainScene: TCastleScene; DOMElement: TDOMElement);

  { Find named Effect node, and make sure it has a float uniform with
    given name. }
  function FindEffectNode(const EffectNodeName: string;
    const UniformName: string): TEffectNode;
  begin
    Result := MainScene.RootNode.FindNodeByName(
      TEffectNode, EffectNodeName, false) as TEffectNode;

    { checks }
    if Result = nil then
      OnWarning(wtMajor, 'Level', Format('%s node not found',
        [EffectNodeName])) else
    if Result.Fields.IndexOf(UniformName) = -1 then
      OnWarning(wtMajor, 'Level', Format('%s node found, but without %s uniform',
        [EffectNodeName, UniformName])) else
    if not (Result.Fields.ByName[UniformName] is TSFFloat) then
      OnWarning(wtMajor, 'Level', Format('%s.%s uniform found, but is not SFFloat',
        [EffectNodeName, UniformName]));
  end;

begin
  inherited;
  Elevators := TElevatorList.Create(true);
  Elevators.Add(TElevator.Create('stages/street/elevator_1.x3d', AWorld, Self, 10));
  Elevators.Add(TElevator.Create('stages/street/elevator_2.x3d', AWorld, Self, 10));
  Elevators.Add(TElevator.Create('stages/tube/elevator_1.x3d', AWorld, Self, 10));
  Elevators.Add(TElevator.Create('stages/outdoors/elevator_1.x3d', AWorld, Self, 10));
  Elevators.Add(TElevator.Create('stages/above/elevator_1.x3d', AWorld, Self, 10));
  Elevators.Add(TElevator.Create('stages/above/elevator_2.x3d', AWorld, Self, 10));
  Elevators.Add(TElevator.Create('stages/above/elevator_3.x3d', AWorld, Self, 10));
  Elevators.Add(TElevator.Create('stages/above/elevator_4.x3d', AWorld, Self, 10));
  Lights := TVector3SingleList.Create;

  BrightnessEffect := FindEffectNode('BrightnessEffect', DistanceFactorUniform);
  BackgroundEffect := FindEffectNode('BackgroundEffect', MorningUniform);
end;

destructor TLevel1.Destroy;
begin
  FreeAndNil(Elevators);
  FreeAndNil(Lights);
  inherited;
end;

{ Hermite interpolation between two values.
  Just like GLSL smoothstep:
  http://www.khronos.org/opengles/sdk/docs/manglsl/xhtml/smoothstep.xml }
function SmoothStep(const Edge0, Edge1, X: Single): Single;
begin
  Result := Clamped((X - Edge0) / (Edge1 - Edge0), 0.0, 1.0);
  Result := Result * Result * (3.0 - 2.0 * Result);
end;

procedure TLevel1.Update(const SecondsPassed: Single; var RemoveMe: TRemoveType);
var
  E: TElevator;
  DistanceToClosestLight, S, DistanceFactor, MorningFactor: Single;
  PlayerPos, Projected: TVector3Single;
  I: Integer;
const
  DistanceToSecurity = 4.0;
  DistanceToDanger = 8.0;
begin
  inherited;
  if Player = nil then Exit; // paranoia, TODO: check, possibly not needed
  for E in Elevators do
    E.Update;

  PlayerPos := Player.Position;

  { calculate and use distance to the nearest light source }

  DistanceToClosestLight := 10000; // not just MaxSingle, since we will Sqr this
  for I := 0 to Lights.Count - 1 do
  begin
    S := PointsDistanceSqr(Lights.L[I], PlayerPos);
    if S < Sqr(DistanceToClosestLight) then
      DistanceToClosestLight := Sqrt(S);
  end;

  DistanceFactor := SmoothStep(DistanceToSecurity, DistanceToDanger,
    DistanceToClosestLight);

  (BrightnessEffect.Fields.ByName[DistanceFactorUniform] as TSFFloat).
    Send(DistanceFactor);

  if DistanceFactor < 0.5 then
  begin
    ResourceHarpy.RunAwayLife := 10.0 { anything >= 1.0, to run always };
    ResourceHarpy.RunAwayDistance := MapRange(DistanceFactor, 0.0, 0.5,
      100, 10);
  end else
    ResourceHarpy.RunAwayLife := 0.0 { never run };

  { calculate and use "morning", which shows player progress on skybox }
  Projected := PointOnLineClosestToPoint(MorningEmpty, MorningFull, PlayerPos);
  MorningFactor := PointsDistance(MorningEmpty, Projected) /
                   PointsDistance(MorningEmpty, MorningFull);
  Clamp(MorningFactor, 0, 1);
  (BackgroundEffect.Fields.ByName[MorningUniform] as TSFFloat).
    Send(MorningFactor);


  if GameWinBox.PointInside(PlayerPos) then
    GameWin := true;
end;

function TLevel1.Placeholder(const Shape: TShape;
  const PlaceholderName: string): boolean;
begin
  Result := inherited;
  if Result then Exit;

  if IsPrefix('LightPos', PlaceholderName) then
  begin
    Lights.Add(Shape.BoundingBox.Middle);
    Exit(true);
  end;

  if PlaceholderName = 'MorningEmpty' then
  begin
    MorningEmpty := Shape.BoundingBox.Middle;
    Exit(true);
  end;

  if PlaceholderName = 'MorningFull' then
  begin
    MorningFull := Shape.BoundingBox.Middle;
    Exit(true);
  end;

  if PlaceholderName = 'GameWin' then
  begin
    GameWinBox := Shape.BoundingBox;
    Exit(true);
  end;
end;

initialization
  { register our level logic classes }
  LevelLogicClasses['Level1'] := TLevel1;
end.
