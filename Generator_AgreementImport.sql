/*
Author: Seth Low
Date: May 11, 2016
Description: This should help build a ImportFile from the TSI DBs
*/

DECLARE		
	@destBU INT = 120 -- This is the ID of the BusinessUnit we are targetting
	, @destBUCode VARCHAR(10)
	, @agrMapppingID VARCHAR(250) = 'HARDCODE'
	, @agrGrpRefID VARCHAR(250) = 'HARDCODE'

	, @perpAgrItmImpRef VARCHAR(250) = 'HARDCODE'
	, @pifAgrItmImpRef VARCHAR(250) = 'HARDCODE'
	, @bSchImpRef VARCHAR(250) = 'HARDCODE'

SET @destBUCode = (SELECT b.Code FROM BusinessUnit b WHERE b.BusinessUnitId = @destBU)

IF (Object_ID('tempdb..#AgreementToImport') IS NOT NULL) DROP TABLE #AgreementToImport
IF (Object_ID('tempdb..#TargetList') IS NOT NULL) DROP TABLE #TargetList


SELECT ROW_NUMBER() over (partition by na.MemberID ORDER BY na.MemberID ASC) as  ROW_Num
		, *
INTO #TargetList
FROM  [TSI_tactical].[dbo].[Storage_Newbury_AgreementMove] na 

SELECT ROW_NUMBER() over (partition by na.MemberID ORDER BY na.MemberID ASC) as  ROW_Num
		, na.MEMBERID AS [OwnerId] --MemberID
      ,@agrMapppingID AS [MappingId] --Agreement ImportRef
      ,CONCAT(na.MEMBERID,'NA',na.Row_Num) AS [AgreementReferenceId] -- Composite ID used for mapping between staging tables.
      , @destBUCode [FacilityCode] -- BusinessUnitCode
      ,'' AS [AccountId] -- Responsible Party MemberID
      ,GETDATE() AS [StartDate] -- When did the agreement start
      ,0 AS [Balance] -- Any balance owed
      ,NULL AS [Barcode] -- NULL - This is not required for an agreement import
      ,@agrGrpRefID AS [AgreementGroupReferenceId] -- AgreementGroup.ImportRef
      ,1 AS [AgreementRoleTypeId] -- 1?  Not positive on this one
      ,NULL AS [PrimaryAgreementId] -- ID of the primary agreement that this is an add-on too, or NULL if this is the primary
      ,100 AS [PrimarySplit] -- 100 - Percentage for who is responsible
      ,0 AS [SecondarySplit] -- 0 - Secondary ammount placed towards the agreement
      ,0 AS [FromExternal] -- 0 - Is the agreemennt from an external source
      ,1 AS [Sequence] -- 1 - This is always 1 until I channge it during the import process
      ,NULL AS [SalesAdvisor] -- STAGING COLUMN - Personal reference only always NULL
      ,NULL AS [PromotionName]-- STAGING COLUMN - Personal reference only always NULL
      ,NULL AS [SplitType]-- STAGING COLUMN - Personal reference only always NULL
      ,NULL AS [OriginalStartDate]-- STAGING COLUMN - Personal reference only always NULL
      ,NULL AS [CancelDate]-- STAGING COLUMN - Personal reference only always NULL
      ,NULL AS [CancelReason]-- STAGING COLUMN - Personal reference only always NULL
      ,NULL AS [SuspStartDate]-- STAGING COLUMN - Personal reference only always NULL
      ,NULL AS [SupsEndDate]-- STAGING COLUMN - Personal reference only always NULL
      ,NULL AS [SuspReason]-- STAGING COLUMN - Personal reference only always NULL
      ,NULL AS [FreezeFee]-- STAGING COLUMN - Personal reference only always NULL
      ,NULL AS [ObligationDate]-- STAGING COLUMN - Personal reference only always NULL
      ,NULL AS [FormOfPayment]-- STAGING COLUMN - Personal reference only always NULL
      ,NULL AS [LocPrefix]-- STAGING COLUMN - Personal reference only always NULL
      ,NULL AS [ExternalAgreementID]-- STAGING COLUMN - Personal reference only always NULL
INTO #AgreementToImport
FROM #targetlist na 


SELECT a.[AgreementReferenceId] -- AgreementReferenceID from AgreementToImport
      ,@perpAgrItmImpRef AS [MappingId] -- If this is perpetual then the ImportRef from ItemTermsLocation, if it is PIF then this is the BundlePrice.ImportRef
      , CONCAT(a.AgreementReferenceID,'ITM',a.ROW_Num) AS [ItemReferenceId] -- CompositeID for usually AgreementReferenceID + Number of the item
      , 0 AS [DownPaymentAmount] -- 0 - How much of a downn payment was made, will normally be 0, I don't know if this function actually works
      ,1 AS [InitialQuantity] -- 1 - Initial quantity will be 1
      ,0 AS [Price] -- 0 -- Keep this at 0 for now
      ,1 AS [Quantity] -- Obligation is calculated should be 1
      ,0 AS [Installments] -- 0 - TSI Doesn't do installments
      ,29.99 AS [RecurringPrice] -- Recurring price for each billing
      ,1 AS [BundleGroupId] -- 1 This always seems to be 1 don't know if this funtion is working
      ,@bSchImpRef AS [BillingScheduleRefId] -- The ImportRef from BillingSchedule
INTO #AgreementItemsToImport
  FROM #AgreementToImport a
 ORDER BY a.AgreementReferenceId DESC
  
IF(OBJECT_ID('tempdb..#AgreementItemPaysourcesToImport') IS NOT NULL) DROP TABLE #AgreementItemPaysourcesToImport

;WITH 
	CTE_CAData
		AS (
			SELECT DISTINCT a.OwnerId
					--, a.AgreementReferenceId
					, ai.ItemReferenceId
					, ca.ClientAccountId AS ClientAccount
					, ca.*
			FROM #AgreementToImport a
			INNER JOIN #AgreementItemsToImport ai ON a.AgreementReferenceID = ai.AgreementReferenceID
			INNER JOIN dbo.PartyRole p (NOLOCK) ON p.RoleID = a.OwnerId
			INNER JOIN dbo.ClientAccountParty cap (NOLOCK) ON cap.PartyId = p.PartyID
			INNER JOIN dbo.ClientAccount ca (NOLOCK) ON ca.ClientAccountId = cap.ClientAccountId
			WHERE 1=1
				AND ca.IsActive = 1
				AND cap.IsActive = 1
				AND ca.Status = 1
				AND ca.IsExternal = 0
				AND ca.Name LIKE 'PRIMARY%'
				AND ai.ItemReferenceID = '4641358NA1ITM1'
			)
SELECT DISTINCT ai.[ItemReferenceId] --[ItemReferenceId] from AgreementItemsToImport
      ,c.ClientAccount AS [PaySourceReferenceId] -- Active Client Account of Member
      ,1 AS [IsPercentage] -- 1 Is the amount allocated a percentage total
      ,1 AS [Amount] -- Amount, how much is going on this paysource, in these cases the value will always be 1
      ,ai.[BillingScheduleRefId] AS [MappingId] -- BillingSchedule.ImportRef
INTO #AgreementItemPaysourcesToImport
  FROM #AgreementItemsToImport ai
  INNER JOIN #AgreementToImport a ON a.AgreementReferenceId = ai.AgreementReferenceId
  LEFT JOIN CTE_CAData c ON c.ItemReferenceID = ai.ItemReferenceID



--SELECT COUNT(*) 
SELECT *
		
FROM #AgreementToImport

--SELECT COUNT(*) 
SELECT *
FROM #AgreementItemsToImport

--SELECT COUNT(*) 
SELECT *
FROM #AgreementItemPaysourcesToImport




/*
DROP TABLE #AgreementToImport
DROP TABLE #AgreementItemsToImport
DROP TABLE #AgreementItemPaysourcesToImport
*/


/*
--SELECT * FROM [TSI_tactical].[dbo].[Storage_Newbury_AgreementMove] na 
--SELECT OwnerID, COUNT(OwnerID) FROM #AgreementToImport GROUP BY OwnerID ORDER BY 2 DESC
--SELECT * FROM [TSI_tactical].[dbo].[Storage_Newbury_AgreementMove] na WHERE MemberID = '3189669'


SELECT * FROM #AgreementItemPaysourcesToImport WHERE ItemReferenceID = '4641358NA1ITM1'

SELECT ItemReferenceID , cOUNT(ItemReferenceID) FROM #AgreementItemPaysourcesToImport GROUP BY ItemReferenceID  ORDER BY 2 DESC


*/