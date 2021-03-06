unit DLogger.Log;

interface

uses
  System.SysUtils, System.TypInfo, Generics.Collections, Winapi.Windows,
  System.Classes, System.TimeSpan;

type
  TLogLevel = (TRACE, DEBUG, INFO, WARNING, ERROR, FATAL, OFF);

  ILogAppender = interface
    ['{200C5AA9-9CBE-4662-B358-83052F5500DC}']
    procedure Append(const Level: TLogLevel; const Value: String);
  end;

  ILogger = interface
    ['{10F97490-60F6-4616-BE3F-D93FAE41AFF1}']
    function GetName: string;

    procedure SetLogLevel(const Value: TLogLevel);

    function GetIsDebugEnabled: Boolean;
    function GetIsInfoEnabled: Boolean;
    function GetIsWarnEnabled: Boolean;
    function GetIsErrorEnabled: Boolean;
    function GetIsTraceEnabled: Boolean;
    function GetIsFatalEnabled: Boolean;

    procedure Trace(const msg: string);
    procedure TraceFormat(const msg: string; const args: array of const);

    procedure Debug(const msg: string); overload;
    procedure Debug(const msg: string; e: Exception); overload;
    procedure DebugFormat(const msg: string; const args: array of const); overload;
    procedure DebugFormat(const format: string; const args: array of const; e: Exception); overload;

    procedure Info(const msg: string);overload;
    procedure Info(const msg: string; e: Exception); overload;
    procedure InfoFormat(const msg: string; const args: array of const);overload;
    procedure InfoFormat(const format: string; const args: array of const; e: Exception); overload;

    procedure Warn(const msg: string); overload;
    procedure Warn(const msg: string; e: Exception); overload;
    procedure WarnFormat(const msg: string; const args: array of const); overload;
    procedure WarnFormat(const msg: string; const args: array of const; e: Exception); overload;

    procedure Error(const msg: string); overload;
    procedure Error(const msg: string; e: Exception); overload;
    procedure ErrorFormat(const msg: string; const args: array of const); overload;
    procedure ErrorFormat(const msg: string; const args: array of const; e: Exception); overload;

    procedure Fatal(const msg: string); overload;
    procedure Fatal(const msg: string; e: Exception); overload;
    procedure FatalFormat(const msg: string; const args: array of const); overload;
    procedure FatalFormat(const msg: string; const args: array of const; e: Exception); overload;

    property IsDebugEnabled: Boolean read GetIsDebugEnabled;
    property IsInfoEnabled: Boolean read GetIsInfoEnabled;
    property IsWarnEnabled: Boolean read GetIsWarnEnabled;
    property IsErrorEnabled: Boolean read GetIsErrorEnabled;
    property IsFatalEnabled: Boolean read GetIsFatalEnabled;
  end;

  ILoggerFactory = interface
    ['{1CDEE569-3E91-4A5D-8173-F21305DB8BF2}']
    function GetDefaultLogger: ILogger;
    function GetLogger(const Name: string): ILogger; overload;
    function GetLogger(AClass: TClass): ILogger; overload;
    function GetLogger(typeInfo: PTypeInfo): ILogger; overload;

    procedure AddAppender(Appender: ILogAppender);

    function GetLogLevel: TLogLevel;
    procedure SetLogLevel(ALogLevel: TLogLevel);
  end;

  TLoggerNotifyAppenders = procedure (const Level: TLogLevel; const Value: string) of object;

  TLoggerFactory = class(TInterfacedObject, ILoggerFactory)
  strict private
    class var Instance: ILoggerFactory;
    class var FLoggers: TDictionary<String, ILogger>;
    class var FAppenders: TList<ILogAppender>;
    class var FLogLevel: TLogLevel;
    class var FSyncAppenders: TMultiReadExclusiveWriteSynchronizer;
    class var FSyncLoggers: TMultiReadExclusiveWriteSynchronizer;
  strict private
    class constructor Create;
    class destructor Destroy;

  private
    procedure NotifyAppenders(const Level: TLogLevel; const Value: string);
    class procedure Finalize;
  protected
    function CreateLogger(const Name: string): ILogger;virtual;
  public
    class function GetInstance: ILoggerFactory;

    function GetDefaultLogger: ILogger;
    function GetLogger(const Name: string): ILogger; overload;
    function GetLogger(AClass: TClass): ILogger; overload;
    function GetLogger(typeInfo: PTypeInfo): ILogger; overload;

    function GetLogLevel: TLogLevel;
    procedure SetLogLevel(ALogLevel: TLogLevel);

    procedure AddAppender(Appender: ILogAppender);

    procedure AfterConstruction; override;
  end;

  TLoggable = class(TObject)
  private
    FLogger: ILogger;
  protected
    property Logger: ILogger read FLogger;
  public
    procedure AfterConstruction; override;
  end;

function LoggerFactory: ILoggerFactory;

implementation

uses DLogger.Log.Logger;

function LoggerFactory: ILoggerFactory;
begin
  Result := TLoggerFactory.GetInstance;
end;
{ TLoggerFactory }

procedure TLoggerFactory.AddAppender(Appender: ILogAppender);
begin
  FSyncAppenders.BeginWrite;
  try
    if not FAppenders.Contains(Appender) then
    begin
      FAppenders.Add(Appender);
    end;
  finally
    FSyncAppenders.EndWrite;
  end;
end;

procedure TLoggerFactory.AfterConstruction;
begin
  inherited;
  FLogLevel := TLogLevel.INFO;
end;

class constructor TLoggerFactory.Create;
begin
  TLoggerFactory.FSyncAppenders := TMultiReadExclusiveWriteSynchronizer.Create;
  TLoggerFactory.FSyncLoggers := TMultiReadExclusiveWriteSynchronizer.Create;
  TLoggerFactory.Instance := TLoggerFactory.Create;

  TLoggerFactory.FLoggers := TDictionary<String, ILogger>.Create;
  TLoggerFactory.FAppenders := TList<ILogAppender>.Create;
end;

function TLoggerFactory.CreateLogger(const Name: string): ILogger;
begin
  Result := TLogger.Create(name, FLogLevel, NotifyAppenders);
end;

class destructor TLoggerFactory.Destroy;
begin
  TLoggerFactory.FLoggers.Free;
  TLoggerFactory.FAppenders.Clear;
  TLoggerFactory.FAppenders.Free;
  TLoggerFactory.Instance := nil;
  TLoggerFactory.FSyncAppenders.Free;
  TLoggerFactory.FSyncLoggers.Free;
end;

class procedure TLoggerFactory.Finalize;
begin
  TLoggerFactory.Instance := nil;
end;

function TLoggerFactory.GetDefaultLogger: ILogger;
begin
  Result := GetLogger('Default');
end;

class function TLoggerFactory.GetInstance: ILoggerFactory;
begin
  Result := TLoggerFactory.Instance;
end;

function TLoggerFactory.GetLogger(AClass: TClass): ILogger;
begin
  Result := GetLogger(AClass.ClassName);
end;

function TLoggerFactory.GetLogLevel: TLogLevel;
begin
  Result := FLogLevel;
end;

procedure TLoggerFactory.NotifyAppenders(const Level: TLogLevel;const Value: string);
var
  vAppender: ILogAppender;
begin
  FSyncAppenders.BeginRead;
  try
    for vAppender in FAppenders do
    begin
      vAppender.Append(Level, Value);
    end;
  finally
    FSyncAppenders.EndRead;
  end;
end;

procedure TLoggerFactory.SetLogLevel(ALogLevel: TLogLevel);
var
  Logger: ILogger;
begin
  if (FLogLevel <> ALogLevel) then
  begin
    FLogLevel := ALogLevel;

    FSyncLoggers.BeginRead;
    try
      for Logger in FLoggers.Values do
      begin
        Logger.SetLogLevel(FLogLevel);
      end;
    finally
      FSyncLoggers.EndRead;
    end;

    NotifyAppenders(TRACE, Format('LogLevel changed to %s', [GetEnumName(TypeInfo(TLogLevel), Ord(FLogLevel))]));
  end;
end;

function TLoggerFactory.GetLogger(const Name: string): ILogger;
begin
  FSyncLoggers.BeginRead;
  try
    if not FLoggers.TryGetValue(name, Result) then
    begin
      FSyncLoggers.BeginWrite;
      try
        Result := CreateLogger(Name);

        FLoggers.Add(name, Result);
      finally
        FSyncLoggers.EndWrite;
      end;
    end;
  finally
    FSyncLoggers.EndRead;
  end;
end;

function TLoggerFactory.GetLogger(typeInfo: PTypeInfo): ILogger;
begin
  Result := GetLogger(String(typeInfo^.Name));
end;

{ TLoggable }

procedure TLoggable.AfterConstruction;
begin
  inherited;
  FLogger := LoggerFactory.GetLogger(ClassType);
end;

initialization
  TLoggerFactory.GetInstance;

finalization
  TLoggerFactory.Finalize;

end.
