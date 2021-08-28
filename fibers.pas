unit fibers;

{$mode objfpc}{$H+}
{$AsmMode Intel}

interface

uses
  SysUtils;

type
  EAlreadyOneMainFiberException = class(Exception);
  EFiberNotActiveException = class(Exception);
  ENotAFiberException = class(Exception);
  ESystemError = class(Exception);

  { TFiber }

  TFiber = class
  protected
    FContext: {$IfDef WINDOWS}Pointer{$Else}jmp_buf{$EndIf};
    FLastFiber: TFiber;
  public
    procedure SwitchTo(TargetFiber: TFiber);
    procedure Return;
  end;

  { TMainFiber }

  TMainFiber = class(TFiber)
  public
    constructor Create;
    destructor Destroy; override;
  end;

  { TExecutableFiber }

  TExecutableFiber = class(TFiber)
  private
    {$IfNDef WINDOWS}
    FStack: Pointer;
    {$EndIf}
  protected
    procedure Execute; virtual; abstract;
  public
    constructor Create(StackSize: SizeInt = DefaultStackSize);
    destructor Destroy; override;
  end;

function GetMainFiber: TMainFiber; inline;
function GetCurrentFiber: TFiber; inline;
procedure Switch(TargetFiber: TFiber); inline;
implementation
{$IfDef WINDOWS}
uses
  windows;
// see WinBase.h:316
type
  PFIBER_START_ROUTINE = procedure (lpFiberParameter: LPVOID); stdcall;
  LPFIBER_START_ROUTINE = PFIBER_START_ROUTINE;

// See WinBase.h:1461
procedure SwitchToFiber(lpFiber: LPVOID); stdcall; external 'kernel32' name 'SwitchToFiber';
procedure DeleteFiber(lpFiber: LPVOID); stdcall; external 'kernel32' name 'DeleteFiber';
function ConvertFiberToThread: BOOL; stdcall; external 'kernel32' name 'ConvertFiberToThread';
function CreateFiber(dwStackSize: SIZE_T; lpStartAddress: LPFIBER_START_ROUTINE; lpParameter: LPVOID): LPVOID; stdcall; external 'kernel32' name 'CreateFiber';
function ConvertThreadToFiber(lpParameter: LPVOID): LPVOID; stdcall; external 'kernel32' name 'ConvertThreadToFiber';
{$EndIf}

threadvar ThreadMainFiber: TMainFiber;
threadvar CurrentFiber: TFiber;

procedure ContextSwitch(FromFiber: TFiber; ToFiber: TFiber); inline;
begin
  {$IfDef WINDOWS}
    SwitchToFiber(ToFiber.FContext);
  {$Else}
  if setjmp(FromFiber.FContext) = 0 then
    longjmp(ToFiber.FContext, 1);
  {$EndIf}
  // once we return here, we are again at FromFiber
  CurrentFiber := FromFiber;
end;

function GetMainFiber: TMainFiber;
begin
  Result := ThreadMainFiber;
end;

function GetCurrentFiber: TFiber;
begin
  Result := CurrentFiber;
end;

procedure Switch(TargetFiber: TFiber);
begin
  if not Assigned(CurrentFiber) then
    raise ENotAFiberException.Create('Can only switch from a fiber');
  CurrentFiber.SwitchTo(TargetFiber);
end;

{ TFiber }

procedure TFiber.SwitchTo(TargetFiber: TFiber);
begin
  if CurrentFiber <> Self then
    raise EFiberNotActiveException.Create('Can only call SwitchTo from the currently active Fiber');
  if TargetFiber = Self then
    raise EFiberNotActiveException.Create('Can not switch to the currently active fiber');
  TargetFiber.FLastFiber := Self;
  ContextSwitch(Self, TargetFiber);;
end;

procedure TFiber.Return;
begin
  if CurrentFiber <> Self then
    raise EFiberNotActiveException.Create('Can only call Return from the currently active Fiber');
  if Assigned(FLastFiber) then
    ContextSwitch(Self, FLastFiber)
  else
    ContextSwitch(Self, ThreadMainFiber);
end;

{ TMainFiber }

constructor TMainFiber.Create;
begin
  inherited Create;
  if Assigned(ThreadMainFiber) then
    raise EAlreadyOneMainFiberException.Create('There is already one main fiber for this thread');
  CurrentFiber := Self;
  ThreadMainFiber := Self;
  {$IfDef WINDOWS}
  FContext := ConvertThreadToFiber(Self);
  if not Assigned(FContext) then
    raise ESystemError.Create('Error calling ConvertThreadToFiber: ' + GetLastError.ToString);
  {$EndIf}
end;

destructor TMainFiber.Destroy;
begin
  {$IfDef WINDOWS}
  if not ConvertFiberToThread then
    raise ESystemError.Create('Error calling ConvertFiberToThread: ' + GetLastError.ToString);
  {$EndIf}
  ThreadMainFiber := nil;
  inherited Destroy;
end;

{ TExecutableFiber }

{$IfDef Windows}

procedure FiberEntryPoint(lpFiberParameter: LPVOID); stdcall;
begin
  CurrentFiber := TFiber(lpFiberParameter);
  TExecutableFiber(lpFiberParameter).Execute;
  TExecutableFiber(lpFiberParameter).Return;
end;
{$EndIf}

constructor TExecutableFiber.Create(StackSize: SizeInt);
{$IfDef WINDOWS}
begin
  inherited Create;
  FLastFiber := GetCurrentFiber;
  FContext := CreateFiber(StackSize, @FiberEntryPoint, Self);
  if not Assigned(FContext) then
    raise ESystemError.Create('Error calling CreateFiber: ' + GetLastError.ToString);
end;
{$Else}
var
  StackMem, StackPtr, BasePtr, NewStackPtr, NewBasePtr: Pointer;
  FrameSize: SizeInt;
  backjump: jmp_buf;
begin
  inherited Create;
  FLastFiber := GetCurrentFiber;
  StackMem := GetMem(StackSize);
  if setjmp(backjump) <> 0 then
    Exit;
  // setup stack: copy current frame to new stack
  asm
  MOV StackPtr, RSP
  MOV BasePtr, RBP
  end;
  FrameSize := BasePtr - StackPtr;
  NewBasePtr := StackMem + StackSize;
  NewStackPtr := NewBasePtr - FrameSize;
  Move(PByte(StackPtr)^, PByte(NewStackPtr)^, FrameSize);
  // set new stack as current stack
  asm
  MOV RSP, NewStackPtr
  MOV RBP, NewBasePtr
  end;
  // save context to continue later on and jump back to return from create
  if setjmp(FContext) = 0 then
    longjmp(backjump, 1);
  CurrentFiber := Self;
  // Execute functionality
  Execute;
  // return to the last function that called you
  Return;
end;
{$EndIf}

destructor TExecutableFiber.Destroy;
begin
  {$IfDef WINDOWS}
  DeleteFiber(FContext);
  {$Else}
  Freemem(FStack);
  {$EndIf}
  inherited Destroy;
end;

end.

