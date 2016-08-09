
/*
Author: Seth Low
Date: February 3, 2016
Purpose: This was designed to reverse a payment  and then all transactions on a group of invoices. 

********* IF this is getting used for another project, you'll have to change the root staging table on all queries *********
*/


DECLARE @Update INT = 1,
		@MemberID VARCHAR(10) = NULL,
		@Validate INT = 0,
		@TxInvoiceID INT = NULL,
		@date DATE = '7/1/2016'
		

		;



--IF (OBJECT_ID('TSI_Tactical.dbo.[Storage_March_Freeze_InvoiceIssue_FINAL]') IS NOT NULL) DROP TABLE [TSI_tactical].dbo.[Storage_March_Freeze_InvoiceIssue_FINAL]
IF (Object_ID('tempdb..#Reverselist') IS NOT NULL) DROP TABLE #Reverselist;
IF(Object_ID('tempdb..#ClientAccountStaging') IS NOT NULL) DROP TABLE #ClientAccountStaging;
IF(Object_ID('tempdb..#Temp') IS NOT NULL) DROP TABLE #Temp
IF(Object_ID('tempdb..#TransactionStaging') IS NOT NULL) DROP TABLE #TransactionStaging;
IF(Object_ID('tempdb..#Staging') IS NOT NULL) DROP TABLE #Staging;
IF(Object_ID('tempdb..#Exclusion') IS NOT NULL) DROP TABLE #Exclusion;

IF(Object_ID('tempdb..#Reverse') IS NOT NULL) DROP TABLE #Reverse;
IF(Object_ID('tempdb..#NontxPayment') IS NOT NULL) DROP TABLE #NontxPayment;


--SELECT *FROM  TSI_Tactical.[dbo].[Storage_JUNE_Transactions_To_Reverse] r (NOLOCK) WHERE r.TxPaymentID = 'NULL'


SELECT *
INTO #Reverse
FROM  TSI_Tactical.[dbo].[Storage_JULY_TransactionsToRemove] r (NOLOCK) 
WHERE r.TxPaymentId != 'NULL'


/* --This includes the Sponsor transfers
SELECT *
INTO #NontxPayment
FROM TSI_Tactical.[dbo].[Storage_JUNE_Transactions_To_Reverse]


--SELECT t.*
UPDATE r SET r.TxPaymentID = t.ItemId
FROM #NontxPayment r (NOLOCK) 
INNER JOIN dbo.TxTransaction t ON t.TxInvoiceId = r.TxInvoiceId 
WHERE TxPaymentID = 'NULL'
	AND amount != 0 
	AND txtypeid = 4
*/

SELECT	i.PartyRoleID
		, p.RoleID AS MemberID
		, r.TxPaymentID
		, t.TxInvoiceID
		, t.TargetBusinessUnitId AS txtBusinessUnitID
		, t.Amount AS SaleAmount
		, pv.[First Name]
		, pv.[Last Name]
		, mr.MemberAgreementId
		, a.Name AS Agreement
INTO #Staging
--	SELECT *
-- SELECT r.TxPaymentID
--FROM #Reverse r 
FROM #Reverse r 
INNER JOIN TxTransaction t (NOLOCK) ON t.ItemId = r.TxPaymentID AND t.txtypeId = 4
INNER JOIN TxInvoice i (NOLOCK) ON i.TxInvoiceId = t.TxInvoiceID 
INNER JOIN PartyRole p (NOLOCK) ON p.PartyRoleId = i.PartyRoleID
INNER JOIN PartyPropertiesReportingView pv (NOLOCK) ON pv.PartyId= p.PartyID
LEFT JOIN MemberAgreementInvoiceRequest mr (NOLOCK) ON mr.TxInvoiceId = i.TxInvoiceID
LEFT JOIN MemberAgreement m (NOLOCK) ON mr.MemberAgreementId = m.MemberAgreementId
LEFT JOIN Agreement a (NOLOCK) ON  a.AgreementID = m.AgreementId
WHERE 1=1
	AND r.TxPaymentID IS NOT NULL
--	AND r.TxPaymentID = 'NULL' OR r.Txpaymentid is null
	


			SELECT MemberID
					, pa.PartyRoleID
					, Max(cap.ClientAccountId) AS ClientAccountId
			INTO #ClientAccountStaging
			FROM #Staging f
			INNER JOIN PartyRole pa ON pa.RoleId = f.MemberID
			INNER JOIN ClientAccountParty cap ON cap.PartyId = pa.PartyID
			INNER JOIN ClientAccount ca ON ca.ClientAccountId = cap.ClientAccountId 
			WHERE ca.IsActive =1
					AND cap.IsActive = 1
			GROUP BY MemberID, pa.PartyRoleId

--SELECT * FROM #ClientAccountStaging

		-->>> Generating Payment to remove initial transaction

		;
		-->>> These sponsor transfers have no paymentprocessrequest 
		SELECT MemberID,COUNT(MEMBERID) AS Count_Member
		INTO #Exclusion
		FROM #Staging 
			WHERE 1=1
				AND MemberID NOT IN (21534858)
		GROUP BY MemberID
		HAVING COUNT(MEMBERID) > 1
		ORDER BY MemberID DESC

	--->>> PAYMENT INSERT <<<---
		SELECT 
				DISTINCT 
				ISNULL(p.TargetBusinessUnitID, f.txtBusinessUnitId) AS TargetBusinessUnitID
				, GETDATE() AS TargetDate
				, NULL AS CreditCardTypeID
				, NULL AS Reference
				, ISNULL(CAST(p.TxPaymentID AS VARCHAR(20)), 'No TxPaymentID') AS Comments
				, (CASE	t.IsAccountingCredit
						WHEN 0 THEN ISNULL(P.Amount, f.SaleAmount) 
						ELSE ISNULL(-P.Amount, -f.SaleAmount)
						END) AS Amount
				, 'EDT' AS TargetDate_ZoneFormat
				, ISNULL(p.PartyRoleID, cs.PartyRoleId) AS PartyRoleID
				, -1 AS WorkUnitID 
				, 1 AS IsReversal
				, 137 AS TenderTypeID 
				, NULL AS VoidReasonID
				, ISNULL(p.ClientAccountId, cs.ClientAccountID) AS ClientAccountID
				, NULL AS LinkTypeID
				, NULL AS LinkID 
				, NULL AS DeclineReasonID
				, 0 AS IsDeclined
				, GETUTCDATE() AS TargetDate_UTC
				, ISNULL(p.IsMultiInvoice, 0) AS IsMultiInvoice
				, NULL AS TxPaymentGroupID
				, NULL AS FromBilling
		INTO #Temp
		FROM #Staging f --WHERE TxPaymentID IS NULL
		INNER JOIN #ClientAccountStaging cs ON f.MemberID = cs.MemberID
		LEFT JOIN dbo.TxPayment p (NOLOCK) ON p.TxPaymentID = f.TxPaymentID
		LEFT JOIN dbo.TxTransaction t (NOLOCK) ON t.ItemID = p.TxPaymentID AND t.LinkTypeId = 17
		LEFT JOIN #Exclusion e (NOLOCK) ON e.MemberID = f.MemberID
		WHERE t.TxTransactionID IS NULL -- This null prevents the credit transfers from getting included.
			AND IIF(@TxInvoiceID IS NULL, f.TxInvoiceID, @TxInvoiceID) = f.TxInvoiceID
			AND e.MemberID IS NULL

--SELECT * FROM TenderType where name like '%Dues%'-- tendertypeid = 132

--IF(@Update = 1)
--	BEGIN
--		-->>> INSERT Payment	
--		--INSERT INTO TxPayment
--		--SELECT NEWID() AS ObjectID, *
--		--FROM #Temp
--	END


--SELECT * FROM TenderType WHERE TenderTypeID = 137
	--->>> PAYMENT TRANSACTION INSERT <<<---
		


		SELECT DISTINCT 
			t.TxInvoiceId
			, GETDATE() AS TargetDate
			, t.TargetDate AS TransactionDate
			--, t.ItemID AS OriginalPayment --ADDED BY SETH
			, 4 AS TxTypeID
			, NULL AS Quantity
			, CONCAT('ID: ',p.TxPaymentID, ' Is Reversing PaymentID: ', t.ItemID,' These are getting reversed due to Freeze fee issue(StatusUpdate TimeOut).') AS [Description]
			, NULL AS UnitPrice
			, t.Amount
			, 'This is due to StatusUpdate failure, which caused the agreement not to get frozen.' AS Comments
			, t.TargetDate_ZoneFormat
			, (SELECT MAX(DISPLAYORDER) + 1 FROM TxTransaction a WHERE a.TxInvoiceID = t.TxInvoiceId) AS DisplayOrder
			, t.GroupId
			, IIF(CAST(p.TxPaymentId AS INT) IS NULL, t.ItemID, p.TxPaymentID) AS ItemID
			, -1 AS WorkUnitID
			, IIF(t.IsAccountingCredit = 0, 1, 0) AS IsAccountingCredit
			, 0 AS PriceID
			, NULL as BundleID
			, t.BundleGroupId
			, t.TargetBusinessUnitId
			, NULL AS PriceIdType
			, t.LinkTypeId
			, t.LinkId
			, GETUTCDATE() AS TargetDate_UTC
			, t.SalesPersonPartyRoleId
			, NULL AS RecurringDiscount 
			, NULL AS [PIFInstallmentDiscount]
		INTO #TransactionStaging
		FROM #Staging f (NOLOCK)
		INNER JOIN TxTransaction t (NOLOCK) ON t.TxInvoiceId = f.TxInvoiceId AND t.TxTypeId = 4
		LEFT JOIN TxPayment p (NOLOCK) ON p.Comments = CAST(t.ItemID AS varchar(20)) ---THIS WILL NEED TO GET CHANGED TO INNER PRIOR TO BEING SUBMITTED
		LEFT JOIN TXTransaction t2 (NOLOCK) ON t2.ItemID = t.ItemID AND t2.LinkTypeId = 17
		WHERE 1=1
			AND CONVERT(DATE,t.TargetDate,101) = @Date
			AND t.ItemID IS NOT NULL
			AND t2.TxTransactionID IS NULL -->>> This null excludes credit transfers
			AND IIF(@TxInvoiceID IS NULL, f.TxInvoiceID, @TxInvoiceID) = f.TxInvoiceID
		GROUP BY 
			t.TxInvoiceid
			, t.Amount
			, t.TargetDate_ZoneFormat
			, t.GroupID
			, t.ItemID
			, t.BundleGroupID
			, t.TargetBusinessUnitID
			, t.LinkTypeId
			, t.LinkID
			, t.SalesPersonPartyRoleId
			, t.[Description]
			, t.IsAccountingCredit
			, p.TxPaymentId
			, t.TargetDate
		ORDER BY t.TargetDate DESC

IF (@Update = 1)
	BEGIN
	-->>> Transaction for Payment
		INSERT INTO dbo.TxTransaction
			(ObjectId, TxInvoiceId, TargetDate, TxTypeId, Quantity, Description, UnitPrice, Amount, Comments, TargetDate_ZoneFormat, DisplayOrder, GroupId, ItemId, WorkUnitId, IsAccountingCredit, PriceId, BundleId, BundleGroupId, TargetBusinessUnitId, PriceIdType, LinkTypeId, LinkId, TargetDate_UTC, SalesPersonPartyRoleId, RecurringDiscount, PIFInstallmentDiscount)
		SELECT NEWID() AS ObjectID
			, TxInvoiceId
			, TargetDate
			, TxTypeId
			, Quantity
			, Description
			, UnitPrice
			, Amount
			, Comments
			, TargetDate_ZoneFormat
			, DisplayOrder
			, GroupId
			, ItemId
			, WorkUnitId
			, IsAccountingCredit
			, PriceId
			, BundleId
			, BundleGroupId
			, TargetBusinessUnitId
			, PriceIdType
			, LinkTypeId
			, LinkId
			, TargetDate_UTC
			, SalesPersonPartyRoleId
			, RecurringDiscount
			, PIFInstallmentDiscount
		FROM #TransactionStaging t
		WHERE t.TxInvoiceId = IIF(@TxInvoiceID IS NULL, t.TxInvoiceID, @TxInvoiceID)
	END


-->> THIS IS COMMENTED FOR A 1 TIME RUN.  I need to insert the payment transactions in addition to this.
		IF(Object_ID('tempdb..#RemainingTransactions') IS NOT NULL) DROP TABLE #RemainingTransactions;


	--->>> TRANSACTION INSERT <<<---

		SELECT 
				NEWID() AS ObjectId
				, t.TxInvoiceId
				, GETDATE() AS TargetDate
				, t.TxTypeId
				, t.Quantity
				, CONCAT(t.Description, ' - Reversed due to Freeze Fee failure') AS Description
				, t.UnitPrice
				, t.Amount
				, t.Comments
				, t.TargetDate_ZoneFormat
				, (SELECT MAX(DISPLAYORDER) + 1 FROM TxTransaction a WHERE a.TxInvoiceID = f.TxInvoiceId) AS DisplayOrder
				, t.GroupId
				, t.ItemId
				, -1 AS WorkUnitId
				, IIF(t.IsAccountingCredit = 0, 1, 0) AS IsAccountCredit
				, t.PriceId
				, t.BundleId
				, t.BundleGroupId
				, t.TargetBusinessUnitId
				, t.PriceIdType
				, t.LinkTypeId
				, t.LinkId
				, GETUTCDATE() AS TargetDate_UTC
				, t.SalesPersonPartyRoleId
				, t.RecurringDiscount
				, t.PIFInstallmentDiscount
		INTO #RemainingTransactions
		FROM #Staging f (NOLOCK)
		INNER JOIN TxTransaction t (NOLOCK) ON t.TxInvoiceID = f.TxInvoiceID
		WHERE 1=1
			--AND t.txInvoiceId = 18694286
			AND t.TxtypeID NOT IN (100,4)
			AND IIF(@TxInvoiceID IS NULL, f.TxInvoiceID, @TxInvoiceID) = f.TxInvoiceID


IF (@Update = 1)
	BEGIN
		SELECT 1
-->>> Reverse Remaining Transactions
		INSERT INTO dbo.TxTransaction
			(ObjectId, TxInvoiceId, TargetDate, TxTypeId, Quantity, Description, UnitPrice, Amount, Comments, TargetDate_ZoneFormat, DisplayOrder, GroupId, ItemId, WorkUnitId, IsAccountingCredit, PriceId, BundleId, BundleGroupId, TargetBusinessUnitId, PriceIdType, LinkTypeId, LinkId, TargetDate_UTC, SalesPersonPartyRoleId, RecurringDiscount, PIFInstallmentDiscount)
		SELECT *
		FROM #RemainingTransactions

	END




IF (@Update = 0)
	BEGIN	
		
		--SELECT * FROM #Exclusion
		
		--SELECT p.RoleID, s.* 
		----INTO TSI_Tactical.dbo.Storage_May_TransactionsBeingReversed
		--FROM #Staging  s
		--LEFT JOIN PartyRole p ON s.PartyRoleId = p.PartyRoleID
		--WHERE 1=1
		--	AND s.MemberID NOT IN (SELECT MEMBERID FROM #Exclusion)
		--	AND TxInvoiceID = IIF(@TxInvoiceID IS NOT NULL, @TxInvoiceID, TxInvoiceID)

			
		--SELECT s.TxPaymentId, p.PaymentProcessRequestId
		--FROM #Staging s
		--LEFT JOIN PaymentProcessRequest p ON p.TxPaymentId = s.TxPaymentId
		--WHERE s.MemberID IN (SELECT MEMBERID FROM #Exclusion) 
	IF(@TxInvoiceID IS NOT NULL)
		BEGIN
			SELECT p.RoleID
					, pv.[First Name]
					, pv.[Last Name]
					, i.TxInvoiceID
					, i.TargetDate
			FROM TxInvoice i
			INNER JOIN PartyRole p ON p.PartyROleID = i.PartyRoleId
			INNER JOIN PartyPropertiesReportingView pv ON pv.PartyId = p.PartyID 
			WHERE i.TxInvoiceID = IIF(@TxInvoiceID IS NULL, i.TxInvoiceID, @TXinvoiceID)
		END

		SELECT 'ReversingPayment', * FROM #Temp -->> New Payment
		SELECT 'ReversingTransaction',* FROM #TransactionStaging t -->> Reversing Payment Transaction
		SELECT 'TransactionToPayoffOriginal', p.roleid, * 
			FROM #RemainingTransactions r
			LEFT JOIN TxInvoice i ON i.TxInvoiceID = r.TxInvoiceId
			LEFT JOIN PartyRole p ON p.PartyRoleID = i.PartyRoleId  -->> Reversal of remaining transactions
	END


IF (@Validate = 1)
	BEGIN
		SELECT * FROM TxTransaction WHERE TxInvoiceID = @TxInvoiceID
	END

