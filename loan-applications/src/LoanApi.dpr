library LoanApi;

uses
  Web.WebBroker,
  Web.Win.ISAPI,
  LoanWebModule in 'LoanWebModule.pas' {LoanWebModule1: TWebModule};

{$R *.res}

exports
  GetExtensionVersion,
  HttpExtensionProc,
  TerminateExtension;

begin
  Application.Initialize;
  Application.WebModuleClass := WebModuleClass;
  Application.Run;
end.
