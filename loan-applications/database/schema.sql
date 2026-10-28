IF DB_ID(N'LoanApplicationsDb') IS NULL
BEGIN
    CREATE DATABASE LoanApplicationsDb;
END;
GO

USE LoanApplicationsDb;
GO

IF OBJECT_ID(N'dbo.Customers', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Customers
    (
        CustomerId INT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_Customers PRIMARY KEY,
        FullName NVARCHAR(200) NOT NULL,
        Phone NVARCHAR(30) NOT NULL,
        Email NVARCHAR(254) NULL
    );
END;
GO

IF OBJECT_ID(N'dbo.LoanApplications', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.LoanApplications
    (
        ApplicationId INT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_LoanApplications PRIMARY KEY,
        CustomerId INT NOT NULL,
        RequestedAmount DECIMAL(18,2) NOT NULL,
        TermMonths INT NOT NULL,
        Purpose NVARCHAR(1000) NOT NULL,
        Status NVARCHAR(20) NOT NULL
            CONSTRAINT DF_LoanApplications_Status DEFAULT N'New',
        CreatedAt DATETIME2(0) NOT NULL
            CONSTRAINT DF_LoanApplications_CreatedAt DEFAULT SYSDATETIME(),

        CONSTRAINT FK_LoanApplications_Customers
            FOREIGN KEY (CustomerId) REFERENCES dbo.Customers(CustomerId),

        CONSTRAINT CK_LoanApplications_Amount
            CHECK (RequestedAmount > 0),

        CONSTRAINT CK_LoanApplications_Term
            CHECK (TermMonths BETWEEN 1 AND 360),

        CONSTRAINT CK_LoanApplications_Status
            CHECK (Status IN (N'New', N'InReview', N'Approved', N'Rejected'))
    );

    CREATE INDEX IX_LoanApplications_CreatedAt
        ON dbo.LoanApplications(CreatedAt DESC);
END;
GO
