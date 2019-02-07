/*
USE AT YOUR OWN RISK. This script has the potential of ruining your site completely.
Don't even think about running it without having a proper backup available.
Do some decent testing afterwards.

USAGE:
- Changes the values of the variables below
- Run
- Please run it with @doCommit set to 0 first. Several times.
*/
BEGIN TRAN

DECLARE @newDefault NVARCHAR(5)
DECLARE @oldDefault NVARCHAR(5)
DECLARE @portalId INT

SET @newDefault = 'en-GB' -- NEEDS TO BE SET TO THE CULTURECODE FOR HTE NEW DEFAULT. MUST ALREADY BE AVAILABLE ON THE WEBSITE.
SET @portalId = 0         -- NEEDS TO BE SET TO THE PORTALID THAT NEEDS TO BE CHANGED

DECLARE @doReports bit -- also does the reports after the cahnges, if doTabs or doTabModules are turned on
DECLARE @doTabs bit
DECLARE @doTabModules bit
DECLARE @doCommit bit

SET @doCommit = 0       -- SET TO 1 TO ACTUALLY COMMIT THE CHANGES TO THE DATABASE
SET @doReports = 1      -- SET TO 1 TO OUTPUT SOME QUEIRES TO REVIEW THE RESULTS
SET @doTabs = 1         -- SET TO 1 TO CHANGE THE DEFAULT LANGUAGE FOR THE TABS TABLE
SET @doTabModules = 1   -- SET TO 1 TO CHANGE THE DEFAULT LANGUAGE FOR THE TABMODULES TABLE

IF EXISTS(
    SELECT * FROM vw_Tabs T
    WHERE T.PortalID = @portalId
    AND T.UniqueId IN (SELECT DefaultLanguageGuid FROM vw_Tabs WHERE PortalID = @portalId)
    AND T.UniqueId NOT IN (SELECT ISNULL(DefaultLanguageGuid, '00000000-0000-0000-0000-000000000000') FROM vw_Tabs WHERE PortalID = @portalId AND CultureCode = @newDefault)
    )
BEGIN
    PRINT 'LOOK AT RESULTS. These tabs have translations but do not exist in ' + @newDefault
    SELECT CultureCode, TabName, TabPath, IsDeleted FROM vw_Tabs T
    WHERE T.PortalID = @portalId
    AND T.UniqueId IN (SELECT DefaultLanguageGuid FROM vw_Tabs WHERE PortalID = @portalId)
    AND T.UniqueId NOT IN (SELECT ISNULL(DefaultLanguageGuid, '00000000-0000-0000-0000-000000000000') FROM vw_Tabs WHERE PortalID = @portalId AND CultureCode = @newDefault)

    GOTO CANNOT_PROCEED
END

IF EXISTS(
    SELECT TM.* FROM vw_TabModules TM
    WHERE TM.PortalID = @portalId
    AND TM.UniqueId IN (SELECT DefaultLanguageGuid FROM vw_TabModules WHERE PortalID = @portalId)
    AND TM.UniqueId NOT IN (SELECT ISNULL(DefaultLanguageGuid, '00000000-0000-0000-0000-000000000000') FROM vw_TabModules WHERE PortalID = @portalId AND CultureCode = @newDefault)
    )
BEGIN
    PRINT 'LOOK AT RESULTS. These tabmodules have translations but do not exist in ' + @newDefault
    SELECT TM.CultureCode, T.TabName, T.TabPath, TM.ModuleTitle, TM.PaneName, TM.IsDeleted FROM vw_TabModules TM
    INNER JOIN vw_Tabs T ON TM.TabID = T.TabID
    WHERE TM.PortalID = @portalId
    AND TM.UniqueId IN (SELECT DefaultLanguageGuid FROM vw_TabModules WHERE PortalID = @portalId)
    AND TM.UniqueId NOT IN (SELECT ISNULL(DefaultLanguageGuid, '00000000-0000-0000-0000-000000000000') FROM vw_TabModules WHERE PortalID = @portalId AND CultureCode = @newDefault)
    ORDER BY T.TabPath, TM.ModuleTitle

    GOTO CANNOT_PROCEED
END



-- let's have a few reports first
IF @doReports = 1
BEGIN
    -- pages with DefaultLanguageGuid not available in @newDefault
    SELECT * FROM Tabs T WHERE 
        PortalID = @portalId
        AND CultureCode <> @newDefault
        AND NOT DefaultLanguageGuid IS NULL 
        AND NOT EXISTS(SELECT * FROM Tabs T2 WHERE T2.DefaultLanguageGuid = T.DefaultLanguageGuid AND CultureCode = @newDefault)

    -- tabmodules with DefaultLanguageGuid not available in @newDefault
    SELECT T.CultureCode, T.TabPath, T.TabName, TM.ModuleTitle, TM.PaneName FROM TabModules TM 
    INNER JOIN Tabs T ON T.TabID = TM.TabID
    WHERE 
        T.PortalID = @portalId
        AND TM.CultureCode <> @newDefault
        AND NOT TM.DefaultLanguageGuid IS NULL 
        AND NOT EXISTS(SELECT * FROM TabModules TM2 WHERE TM2.DefaultLanguageGuid = TM.DefaultLanguageGuid AND TM2.CultureCode = @newDefault)


END



/*
- Change the DefaultLanguage in Portals table
- Change the DefaultLanguageGuid and LocalizedVersionGuid fields in the Tabs table
- Change the DefaultLanguageGuid and LocalizedVersionGuid fields in the TabModules table
*/

IF @doTabs = 1 OR @doTabModules = 1
BEGIN
    SELECT @oldDefault = DefaultLanguage FROM Portals WHERE PortalID = @portalId
    UPDATE Portals SET DefaultLanguage = @newDefault WHERE PortalID = @portalId
END


DECLARE @tabId INT
DECLARE @cultureCode nvarchar(5)
DECLARE @uniqueId UNIQUEIDENTIFIER
DECLARE @newDefaultLanguageGuid UNIQUEIDENTIFIER
DECLARE @defaultLanguageGuid UNIQUEIDENTIFIER 

IF @doTabs = 1
BEGIN

    SELECT  *  FROM Tabs WHERE PortalID = @portalId ORDER BY ISNULL(DefaultLanguageGuid, UniqueId), CultureCode

    -- FOR EACH tab where culturecode = @oldDefault
    DECLARE curTabs CURSOR FOR SELECT  TabID, CultureCode, UniqueId, DefaultLanguageGuid  FROM Tabs WHERE PortalID = @portalId AND CultureCode = @oldDefault
    OPEN curTabs
    FETCH NEXT FROM curTabs INTO @tabId, @cultureCode, @uniqueId, @defaultLanguageGuid
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- get @UniqueId for @newDefault
        SELECT @newDefaultLanguageGuid = UniqueId FROM Tabs WHERE DefaultLanguageGuid = @uniqueId AND CultureCode = @newDefault

        -- if not exists: it doesn't exist in other languages than @newdefault
        IF @newDefaultLanguageGuid IS NULL
        BEGIN
            -- we will need to detach those from @oldDefault
            UPDATE Tabs SET 
                DefaultLanguageGuid = NULL
                ,LastModifiedOnDate = GETDATE() 
            WHERE DefaultLanguageGuid = @uniqueId
        END
        ELSE --IF NOT @newDefaultLanguageGuid IS NULL
        BEGIN
            -- set all DefaultLanguageGuid to @UniqueId
            UPDATE Tabs SET 
                DefaultLanguageGuid = @newDefaultLanguageGuid 
                ,LastModifiedOnDate = GETDATE() 
            WHERE DefaultLanguageGuid = @uniqueId OR TabId = @tabId
            -- set DefaultLanguageGuid to NULL for @newDefault
            UPDATE Tabs SET 
                DefaultLanguageGuid = NULL 
                ,LastModifiedOnDate = GETDATE() 
            WHERE UniqueId = @newDefaultLanguageGuid
        END

        FETCH NEXT FROM curTabs INTO @tabId, @cultureCode, @uniqueId, @defaultLanguageGuid
    END
    CLOSE curTabs
    DEALLOCATE curTabs

    SELECT  *  FROM Tabs WHERE PortalID = @portalId ORDER BY ISNULL(DefaultLanguageGuid, UniqueId), CultureCode
END

IF @doTabModules =1
BEGIN
    SELECT  *  FROM TabModules WHERE TabId IN (SELECT TabId FROM Tabs WHERE PortalID = @portalId) ORDER BY ISNULL(DefaultLanguageGuid, UniqueId), CultureCode

    DECLARE @tabModuleId INT
    -- FOR EACH tab where culturecode = @oldDefault
    DECLARE curTabMdls CURSOR FOR SELECT  TabModuleID, CultureCode, UniqueId, DefaultLanguageGuid  FROM TabModules WHERE TabId IN (SELECT TabId FROM Tabs WHERE PortalID = @portalId) AND CultureCode = @oldDefault
    OPEN curTabMdls
    FETCH NEXT FROM curTabMdls INTO @tabModuleId, @cultureCode, @uniqueId, @defaultLanguageGuid
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- get @UniqueId for @newDefault
        SET @newDefaultLanguageGuid = NULL
        SELECT @newDefaultLanguageGuid = UniqueId FROM TabModules WHERE DefaultLanguageGuid = @uniqueId AND CultureCode = @newDefault

        -- if not exists: it doesn't exist in other languages than @newdefault
        IF @newDefaultLanguageGuid IS NULL
        BEGIN
            -- we will need to detach those from @oldDefault
            UPDATE TabModules SET 
                DefaultLanguageGuid = NULL
                ,LastModifiedOnDate = GETDATE() 
            WHERE DefaultLanguageGuid = @uniqueId
        END
        ELSE --IF NOT @newDefaultLanguageGuid IS NULL
        BEGIN
            -- set all DefaultLanguageGuid to @UniqueId
            UPDATE TabModules SET 
                DefaultLanguageGuid = @newDefaultLanguageGuid
                ,LastModifiedOnDate = GETDATE() 
            WHERE DefaultLanguageGuid = @uniqueId OR TabModuleId = @tabModuleId
            -- set DefaultLanguageGuid to NULL for @newDefault
            UPDATE TabModules SET 
                DefaultLanguageGuid = NULL 
                ,LastModifiedOnDate = GETDATE() 
            WHERE UniqueId = @newDefaultLanguageGuid
        END

        FETCH NEXT FROM curTabMdls INTO @tabModuleId, @cultureCode, @uniqueId, @defaultLanguageGuid
    END
    CLOSE curTabMdls
    DEALLOCATE curTabMdls

    SELECT  *  FROM TabModules WHERE TabId IN (SELECT TabId FROM Tabs WHERE PortalID = @portalId) ORDER BY ISNULL(DefaultLanguageGuid, UniqueId), CultureCode
END

IF @doReports = 1 AND (@doTabs = 1 OR @doTabModules = 1)
BEGIN
    -- pages with DefaultLanguageGuid not available in @newDefault
    SELECT * FROM Tabs T WHERE 
        PortalID = @portalId
        AND CultureCode <> @newDefault
        AND NOT DefaultLanguageGuid IS NULL 
        AND NOT EXISTS(SELECT * FROM Tabs T2 WHERE T2.DefaultLanguageGuid = T.DefaultLanguageGuid AND CultureCode = @newDefault)

    -- tabmodules with DefaultLanguageGuid not available in @newDefault
    SELECT T.CultureCode, T.TabPath, T.TabName, TM.ModuleTitle, TM.PaneName FROM TabModules TM 
    INNER JOIN Tabs T ON T.TabID = TM.TabID
    WHERE 
        T.PortalID = @portalId
        AND TM.CultureCode <> @newDefault
        AND NOT TM.DefaultLanguageGuid IS NULL 
        AND NOT EXISTS(SELECT * FROM TabModules TM2 WHERE TM2.DefaultLanguageGuid = TM.DefaultLanguageGuid AND TM2.CultureCode = @newDefault)

    SELECT  T.UniqueId, LT.CultureCode, COUNT(LT.TabID)  FROM vw_Tabs T
    INNER JOIN vw_Tabs LT ON LT.DefaultLanguageGuid = T.UniqueId
    WHERE T.PortalID = @portalId
    GROUP BY T.UniqueId, LT.CultureCode
    ORDER BY T.UniqueId

END


IF @doCommit = 1
    COMMIT
ELSE
    ROLLBACK

GOTO ALL_DONE

CANNOT_PROCEED:
    PRINT 'Rolling back'
    ROLLBACK

ALL_DONE:
    PRINT 'ALL DONE'