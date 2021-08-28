program example;

{$mode objfpc}{$H+}

uses
  SysUtils, fibers;

type

  { TWriteFiber }

  TWriteFiber = class(TExecutableFiber)
  protected
    procedure Execute; override;
  public
    Data: String;
  end;

{ TWriteFiber }

procedure TWriteFiber.Execute;
begin
  while not Data.IsEmpty do
  begin
    Write(Data);
    Return;
  end;
  WriteLn;
end;

var
  f: TWriteFiber;
begin
  TMainFiber.Create;
  try
    f := TWriteFiber.Create;
    try
      f.Data := 'Hello';
      Switch(f);
      f.Data := ' ';
      switch(f);
      f.Data := 'World!';
      switch(f);
      f.Data := '';
      Switch(f);
    finally
      f.Free;
    end;
  finally
    GetMainFiber.Free;
  end;
  ReadLn;
end.

