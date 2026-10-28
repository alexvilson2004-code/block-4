unit LoanWebModule;

interface

uses
  System.Classes,
  Web.HTTPApp;

type
  TLoanWebModule = class(TWebModule)
    procedure LoanWebModule1DefaultHandlerAction(
      Sender: TObject;
      Request: TWebRequest;
      Response: TWebResponse;
      var Handled: Boolean);
  end;

function WebModuleClass: TComponentClass;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.DateUtils,
  System.IniFiles,
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.Stan.Def,
  FireDAC.Phys.MSSQL,
  FireDAC.Phys.MSSQLDef,
  FireDAC.DApt,
  StrUtils;

{$R *.dfm}

function WebModuleClass: TComponentClass;
begin
  Result := TLoanWebModule;
end;

function CreateConnection: TFDConnection;
var
  Ini: TIniFile;
  IniFileName: string;
  TrustedConnection: Boolean;
begin
  Result := TFDConnection.Create(nil);
  try
    Result.LoginPrompt := False;

    IniFileName := ExtractFilePath(GetModuleName(HInstance)) + 'api.ini';
    if not FileExists(IniFileName) then
      raise Exception.Create('Configuration file api.ini not found');

    Ini := TIniFile.Create(IniFileName);
    try
      Result.Params.Values['DriverID'] := 'MSSQL';
      Result.Params.Values['Server'] :=
        Ini.ReadString('Database', 'Server', '');
      Result.Params.Values['Database'] :=
        Ini.ReadString('Database', 'Database', '');

      TrustedConnection := Ini.ReadBool(
        'Database', 'TrustedConnection', False);

      if TrustedConnection then
      begin
        Result.Params.Values['OSAuthent'] := 'Yes';
      end
      else
      begin
        Result.Params.Values['User_Name'] :=
          Ini.ReadString('Database', 'User', '');
        Result.Params.Values['Password'] :=
          Ini.ReadString('Database', 'Password', '');
      end;
    finally
      Ini.Free;
    end;

    if (Result.Params.Values['Server'] = '') or
       (Result.Params.Values['Database'] = '') then
      raise Exception.Create('Database configuration is incomplete');

    Result.Connected := True;
  except
    Result.Free;
    raise;
  end;
end;

procedure SendJson(
  Response: TWebResponse;
  StatusCode: Integer;
  Value: TJSONValue);
begin
  Response.StatusCode := StatusCode;
  Response.ContentType := 'application/json; charset=utf-8';
  try
    Response.Content := Value.ToJSON;
  finally
    Value.Free;
  end;
end;

procedure SendError(
  Response: TWebResponse;
  StatusCode: Integer;
  const ErrorCode, MessageText: string);
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  Obj.AddPair('error', ErrorCode);
  Obj.AddPair('message', MessageText);
  SendJson(Response, StatusCode, Obj);
end;

function JsonString(
  Obj: TJSONObject;
  const Name: string): string;
var
  Value: TJSONValue;
begin
  Value := Obj.GetValue(Name);
  if Value = nil then
    Exit('');
  Result := Value.Value;
end;

function ApplicationToJson(Query: TFDQuery): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id',
    TJSONNumber.Create(Query.FieldByName('ApplicationId').AsInteger));
  Result.AddPair('fullName',
    Query.FieldByName('FullName').AsString);
  Result.AddPair('phone',
    Query.FieldByName('Phone').AsString);
  Result.AddPair('email',
    Query.FieldByName('Email').AsString);
  Result.AddPair('requestedAmount',
    TJSONNumber.Create(Query.FieldByName('RequestedAmount').AsFloat));
  Result.AddPair('termMonths',
    TJSONNumber.Create(Query.FieldByName('TermMonths').AsInteger));
  Result.AddPair('purpose',
    Query.FieldByName('Purpose').AsString);
  Result.AddPair('status',
    Query.FieldByName('Status').AsString);
  Result.AddPair('createdAt',
    DateToISO8601(Query.FieldByName('CreatedAt').AsDateTime, False));
end;

procedure TLoanWebModule.LoanWebModule1DefaultHandlerAction(
  Sender: TObject;
  Request: TWebRequest;
  Response: TWebResponse;
  var Handled: Boolean);
var
  Connection: TFDConnection;
  Query: TFDQuery;
  BodyValue: TJSONValue;
  Body: TJSONObject;
  Applications: TJSONArray;
  JsonApplication: TJSONObject;
  Path, Method, StatusValue: string;
  FullName, Phone, Email, Purpose: string;
  AmountText: string;
  RequestedAmount: Double;
  TermMonths, ApplicationId, CustomerId: Integer;
  FormatSettings: TFormatSettings;
begin
  Handled := True;
  Path := Request.PathInfo;
  Method := UpperCase(Request.Method);

  while (Length(Path) > 1) and (Path[Length(Path)] = '/') do
    Delete(Path, Length(Path), 1);

  try
    Connection := CreateConnection;
    try
      Query := TFDQuery.Create(nil);
      try
        Query.Connection := Connection;

        { GET /api/applications }
        if SameText(Path, '/api/applications') and
           (Method = 'GET') then
        begin
          Query.SQL.Text :=
            'SELECT a.ApplicationId, c.FullName, c.Phone, c.Email, ' +
            'a.RequestedAmount, a.TermMonths, a.Purpose, a.Status, a.CreatedAt ' +
            'FROM dbo.LoanApplications a ' +
            'INNER JOIN dbo.Customers c ON c.CustomerId = a.CustomerId ' +
            'ORDER BY a.CreatedAt DESC';

          Query.Open;
          Applications := TJSONArray.Create;
          while not Query.Eof do
          begin
            Applications.AddElement(ApplicationToJson(Query));
            Query.Next;
          end;

          SendJson(Response, 200, Applications);
          Exit;
        end;

        { POST /api/applications }
        if SameText(Path, '/api/applications') and
           (Method = 'POST') then
        begin
          BodyValue := TJSONObject.ParseJSONValue(Request.Content);
          try
            if not (BodyValue is TJSONObject) then
            begin
              SendError(Response, 400, 'invalid_json',
                'Тело запроса должно быть JSON-объектом');
              Exit;
            end;

            Body := TJSONObject(BodyValue);

            FullName := Trim(JsonString(Body, 'fullName'));
            Phone := Trim(JsonString(Body, 'phone'));
            Email := Trim(JsonString(Body, 'email'));
            Purpose := Trim(JsonString(Body, 'purpose'));
            AmountText := JsonString(Body, 'requestedAmount');

            FormatSettings := TFormatSettings.Create;
            FormatSettings.DecimalSeparator := '.';

            if (FullName = '') or (Phone = '') or (Purpose = '') then
            begin
              SendError(Response, 400, 'validation_error',
                'Поля fullName, phone и purpose обязательны');
              Exit;
            end;

            if not TryStrToFloat(
              AmountText, RequestedAmount, FormatSettings) or
              (RequestedAmount <= 0) then
            begin
              SendError(Response, 400, 'validation_error',
                'requestedAmount должен быть положительным числом');
              Exit;
            end;

            if not TryStrToInt(
              JsonString(Body, 'termMonths'), TermMonths) or
              (TermMonths < 1) or (TermMonths > 360) then
            begin
              SendError(Response, 400, 'validation_error',
                'termMonths должен быть числом от 1 до 360');
              Exit;
            end;

            Connection.StartTransaction;
            try
              Query.SQL.Text :=
                'INSERT INTO dbo.Customers (FullName, Phone, Email) ' +
                'OUTPUT INSERTED.CustomerId ' +
                'VALUES (:FullName, :Phone, :Email)';

              Query.ParamByName('FullName').AsString := FullName;
              Query.ParamByName('Phone').AsString := Phone;

              if Email = '' then
                Query.ParamByName('Email').Clear
              else
                Query.ParamByName('Email').AsString := Email;

              Query.Open;
              CustomerId := Query.Fields[0].AsInteger;
              Query.Close;

              Query.SQL.Text :=
                'INSERT INTO dbo.LoanApplications ' +
                '(CustomerId, RequestedAmount, TermMonths, Purpose) ' +
                'VALUES (:CustomerId, :RequestedAmount, :TermMonths, :Purpose)';

              Query.ParamByName('CustomerId').AsInteger := CustomerId;
              Query.ParamByName('RequestedAmount').AsFloat := RequestedAmount;
              Query.ParamByName('TermMonths').AsInteger := TermMonths;
              Query.ParamByName('Purpose').AsString := Purpose;
              Query.ExecSQL;

              Query.SQL.Text :=
                'SELECT CAST(SCOPE_IDENTITY() AS int) AS ApplicationId';
              Query.Open;
              ApplicationId := Query.FieldByName('ApplicationId').AsInteger;
              Query.Close;

              Connection.Commit;
            except
              if Connection.InTransaction then
                Connection.Rollback;
              raise;
            end;

            Response.CustomHeaders.Values['Location'] :=
              '/api/applications/' + IntToStr(ApplicationId);

            JsonApplication := TJSONObject.Create;
            JsonApplication.AddPair('id',
              TJSONNumber.Create(ApplicationId));
            SendJson(Response, 201, JsonApplication);
            Exit;
          finally
            BodyValue.Free;
          end;
        end;

        { PATCH /api/applications/{id}/status }
        if StartsText('/api/applications/', Path) and
           EndsText('/status', Path) and
           (Method = 'PATCH') then
        begin
          ApplicationId := StrToIntDef(
            Copy(Path,
              Length('/api/applications/') + 1,
              Length(Path) - Length('/api/applications/') - Length('/status')),
            0);

          if ApplicationId <= 0 then
          begin
            SendError(Response, 400, 'invalid_id', 'Некорректный ID заявки');
            Exit;
          end;

          BodyValue := TJSONObject.ParseJSONValue(Request.Content);
          try
            if not (BodyValue is TJSONObject) then
            begin
              SendError(Response, 400, 'invalid_json',
                'Тело запроса должно быть JSON-объектом');
              Exit;
            end;

            StatusValue := JsonString(TJSONObject(BodyValue), 'status');

            if not MatchText(StatusValue,
              ['New', 'InReview', 'Approved', 'Rejected']) then
            begin
              SendError(Response, 400, 'validation_error',
                'Допустимые статусы: New, InReview, Approved, Rejected');
              Exit;
            end;

            Query.SQL.Text :=
              'UPDATE dbo.LoanApplications ' +
              'SET Status = :Status ' +
              'WHERE ApplicationId = :ApplicationId';

            Query.ParamByName('Status').AsString := StatusValue;
            Query.ParamByName('ApplicationId').AsInteger := ApplicationId;
            Query.ExecSQL;

            if Query.RowsAffected = 0 then
            begin
              SendError(Response, 404, 'not_found', 'Заявка не найдена');
              Exit;
            end;

            JsonApplication := TJSONObject.Create;
            JsonApplication.AddPair('id',
              TJSONNumber.Create(ApplicationId));
            JsonApplication.AddPair('status', StatusValue);
            SendJson(Response, 200, JsonApplication);
            Exit;
          finally
            BodyValue.Free;
          end;
        end;

        { GET /api/applications/{id} }
        if StartsText('/api/applications/', Path) and
           (Method = 'GET') then
        begin
          ApplicationId := StrToIntDef(
            Copy(Path, Length('/api/applications/') + 1, MaxInt), 0);

          if ApplicationId <= 0 then
          begin
            SendError(Response, 400, 'invalid_id', 'Некорректный ID заявки');
            Exit;
          end;

          Query.SQL.Text :=
            'SELECT a.ApplicationId, c.FullName, c.Phone, c.Email, ' +
            'a.RequestedAmount, a.TermMonths, a.Purpose, a.Status, a.CreatedAt ' +
            'FROM dbo.LoanApplications a ' +
            'INNER JOIN dbo.Customers c ON c.CustomerId = a.CustomerId ' +
            'WHERE a.ApplicationId = :ApplicationId';

          Query.ParamByName('ApplicationId').AsInteger := ApplicationId;
          Query.Open;

          if Query.Eof then
          begin
            SendError(Response, 404, 'not_found', 'Заявка не найдена');
            Exit;
          end;

          SendJson(Response, 200, ApplicationToJson(Query));
          Exit;
        end;

        SendError(Response, 404, 'not_found', 'Маршрут не найден');
      finally
        Query.Free;
      end;
    finally
      Connection.Free;
    end;
  except
    on E: Exception do
    begin
      { Не возвращайте E.Message клиенту: там могут быть детали SQL и подключения. }
      SendError(Response, 500, 'internal_error',
        'Внутренняя ошибка сервера');
    end;
  end;
end;

end.
