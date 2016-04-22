/************************************************************************************************************************
---> TSI Issue #16 - What billed
--> This is a general report displaying what billed the previous night. 
--> It should be monitored however it should not get sent to the client unless specifically asked for.
--> On the rebill days this report should get emailed to Justin and Candace
***********************************************************************************************************************/
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

--CREATE PROCEDURE [dbo].[sp_TSI_WhatBilled]
--AS
--BEGIN

	--TRUNCATE TABLE TSI_Tactical.dbo.Staging_WhatBilled

	if (object_id('tempdb..#RawTxTransaction') is not null) drop table #RawTxTransaction;
	if (object_id('tempdb..#Storage1') is not null) drop table #Storage1;
	if (object_id('tempdb..#Suspensions') is not null) drop table #Suspensions;
	if (object_id('tempdb..#Final') is not null) drop table #Final;

	declare @OriginaBilllingDate date;
	declare @BillingStartDate date;
	declare @BillingEndDate datetime;

	SET @OriginaBilllingDate = '4/1/2016'--CONVERT(DATE, GETDATE(), 101)--'9/4/2015'
	SET @BillingStartDate = '4/1/2016'--CONVERT(DATE, GETDATE(), 101)--'9/4/2015'--
	SET @BillingEndDate = DATEADD(ss,-1,CONVERT(DATETIME,DATEADD(DAY,1,CONVERT(DATE,GETDATE(),101))))--'9/4/2015 23:59:59'--


	--SELECT CONVERT(DATE, GETDATE(), 101)
	--		, CONVERT(DATE, GETDATE(), 101)
	--		, DATEADD(ss,-1,CONVERT(DATETIME,DATEADD(DAY,1,CONVERT(DATE,GETDATE(),101))))
	--SET @BillingStartDate = '8/1/2015'--CONVERT(DATE, GETDATE(), 101)
	--SET @BillingEndDate = GETDATE()--dateadd(day,1,@BillingStartDate)

--
--  Gather all TxTransaction Records that were generated by MTP service accounts for the date range defined above
--  store them in the #RawTxTransaction.  This will only focus on agreement billing.
--  This will be the driver file for the rest of the reporting in this script
--
		select
			pr.RoleID as MemberID
			,pr.PartyRoleID
			,pr.PartyID
			,ma.MemberAgreementId as MemberAgreementId
			,sm.Name as AgreementStatus
			,agmt.Name as AgreementName
			,ma.BusinessUnitId as maBusinessUnitId
			,txi.TargetBusinessUnitId as txiBusinessUnitId
			,bu.name as txtBusinessUnitName
			,convert(date,txi.TargetDate,101) as txiTargetDate
			,convert(date,txi.PaymentDueDate,101) as txiDueDate
			,convert(date,mair.BillDate,101) as mairBillDate
			, txt.TargetBusinessUnitId
			, txt.TxInvoiceId
			, txt.GroupId
			, txt.TxTransactionID
			, txt.TargetDate
			, txt.TxTypeId
			, txt.Amount
			, txt.IsAccountingCredit
			, txt.Description
			, txt.LinkTypeId
			, txt.LinkId
			--,txt.*
		into	#RawTxTransaction
		from
			dbo.TxTransaction txt (nolock) 
			inner join dbo.TxInvoice txi (nolock) on txt.TxInvoiceId = txi.TxInvoiceID
			inner join dbo.WorkUnit wu (nolock) on txt.WorkUnitId = wu.WorkUnitID
			inner join dbo.UserAccount ua (nolock) on wu.UserId = ua.UserAccountId
			-- change the 2 joins below to left to pickup cancellation fees
			inner join dbo.MemberAgreementInvoiceRequest mair (nolock) on txt.TxInvoiceId = mair.TxInvoiceId  -- limits to agreementi billing
			inner join dbo.MemberAgreement ma (nolock) on mair.MemberAgreementId = ma.MemberAgreementId
			left join dbo.Agreement agmt (nolock) on ma.AgreementId = agmt.AgreementId
			--left join dbo.Cancellation can (nolock) on txi.LinkId = can.CancellationId
			--	and txi.LinkTypeId = 3
			--	and can.StateId != 6
			inner join dbo.PartyRole pr (nolock) on txi.PartyRoleId = pr.PartyRoleID
			inner join dbo.BusinessUnit bu (nolock) on txt.TargetBusinessUnitId = bu.BusinessUnitId
			inner join dbo.StatusMap sm (nolock) on sm.StatusId = ma.Status
				and sm.StatusMapType = 5
		where
			txt.TargetDate >= @BillingStartDate and txt.TargetDate < @BillingEndDate  -- limit to date range
			and isnull(ma.FromExternal,0) = 0 -- ignore external agreements
			and ua.ServiceOnly = 1 -- user account limited to servce accounts used by MTP
	--		and txt.Amount != 0  -- ignore $0 transactions (for now)
	--		AND wu.EndPointID != 18626 --->>>TSI Specifc remove when using for other accounts
			-- (mair.MemberAgreementInvoiceRequestId is not null or can.CancellationId is not null)
			--and (ma.MemberAgreementId is null or can.CancellationId is not null)
			--and txt.TxInvoiceId = 14631929
			--and can.CancellationId is not null
			--AND bu.BusinessUnitId IN (54)
			--and ma.MemberAgreementId = 2778092

		--SELECT * FROM BusinessUnit bu WHERE bu.Name like '%Andover%'

		select
			rslt.*
		INTO #Storage1
		from
			(
				select -- Collect all tx records associated to sales
					rt.MemberID
					,rt.MemberAgreementId
					,rt.AgreementStatus
					,rt.AgreementName
					,rt.TxInvoiceId
					,rt.TxTransactionID
					,rt.GroupId as txtGroupId
					,rt.TargetBusinessUnitId as txtBusinessUnitId
					,rt.txtBusinessUnitName
					,rt.mairBillDate
					,rt.txiTargetDate
					,convert(date,rt.TargetDate,101) as txtTargetDate
					,rt.txiDueDate
					,null as maprDueDate
					,case rt.TxTypeId
						when 0 then 'Invalid'
						when 1 then 'Sale'
						when 2 then 'Tax'
						when 3 then 'Discount'
						when 4 then 'Payment'
						when 5 then 'CashBack'
						when 6 then 'Adjustment'
						when 100 then 'DisplayOnly'
						when 101 then 'InvoiceSummary'
						else '?'
					end as txType
					,(case 
						when rt.TxTypeId= 1 then 
							case
								when rt.IsAccountingCredit = 1 then -rt.Amount 
								else rt.Amount
							end 
						else 0
					end) as SaleAmount
					,(case 
						when rt.TxTypeId= 2 then 
							case
								when rt.IsAccountingCredit = 1 then -rt.Amount 
								else rt.Amount
							end 
						else 0
					end) as TaxAmount
					,(case 
						when rt.TxTypeId= 4 then 
							case
								when rt.IsAccountingCredit = 1 then -rt.Amount 
								else rt.Amount
							end 
						else 0
					end) as PaymentAmount
					,(case 
						when rt.TxTypeId not in (1,2,4) then 
							case
								when rt.IsAccountingCredit = 1 then -rt.Amount 
								else rt.Amount
							end 
						else 0
					end) as OtherAmount
					,rt.Description
				from
					#RawTxTransaction rt
				where 
					isnull(rt.LinkTypeId,0) in (1,2)  -- MemberAgreementItem, InvoiceRequestItem

				union all 

				select -- Collect all tx records associated to payments
					rt.MemberID
					,rt.MemberAgreementId
					,rt.AgreementStatus
					,rt.AgreementName
					,rt.TxInvoiceId
					,rt.TxTransactionID
					,rt.GroupId as txtGroupId
					,rt.TargetBusinessUnitId as txtBusinessUnitId
					,rt.txtBusinessUnitName
					,rt.mairBillDate
					,rt.txiTargetDate
					,convert(date,rt.TargetDate,101) as txtTargetDate
					,rt.txiDueDate
					,convert(date,mapr.DueDate,101) as maprDueDate
					,case rt.TxTypeId
						when 0 then 'Invalid'
						when 1 then 'Sale'
						when 2 then 'Tax'
						when 3 then 'Discount'
						when 4 then 'Payment'
						when 5 then 'CashBack'
						when 6 then 'Adjustment'
						when 100 then 'DisplayOnly'
						when 101 then 'InvoiceSummary'
						else '?'
					end as txType
					,(case 
						when rt.TxTypeId= 1 then 
							case
								when rt.IsAccountingCredit = 1 then -rt.Amount 
								else rt.Amount
							end 
						else 0
					end) as SaleAmount
					,(case 
						when rt.TxTypeId= 2 then 
							case
								when rt.IsAccountingCredit = 1 then -rt.Amount 
								else rt.Amount
							end 
						else 0
					end) as TaxAmount
					,(case 
						when rt.TxTypeId= 4 then 
							case
								when rt.IsAccountingCredit = 1 then -rt.Amount 
								else rt.Amount
							end 
						else 0
					end) as PaymentAmount
					,(case 
						when rt.TxTypeId not in (1,2,4) then 
							case
								when rt.IsAccountingCredit = 1 then -rt.Amount 
								else rt.Amount
							end 
						else 0
					end) as OtherAmount
					,rt.Description
				from
					#RawTxTransaction rt
					inner join dbo.MemberAgreementPaymentRequestItem mapri (nolock) on rt.LinkId = mapri.MemberAgreementPaymentRequestItemId
					inner join dbo.MemberAgreementPaymentRequest mapr (nolock) on mapri.MemberAgreementPaymentRequestId = mapr.MemberAgreementPaymentRequestId
				where 
					isnull(rt.LinkTypeId,0) in (3)  -- PaymentRequestItem

				union all

				select -- Collect all remaining tx records 
					rt.MemberID
					,rt.MemberAgreementId
					,rt.AgreementStatus
					,rt.AgreementName
					,rt.TxInvoiceId
					,rt.TxTransactionID
					,rt.GroupId as txtGroupId
					,rt.TargetBusinessUnitId as txtBusinessUnitId
					,rt.txtBusinessUnitName
					,rt.mairBillDate
					,rt.txiTargetDate
					,convert(date,rt.TargetDate,101) as txtTargetDate
					,rt.txiDueDate
					,null as maprDueDate
					,case rt.TxTypeId
						when 0 then 'Invalid'
						when 1 then 'Sale'
						when 2 then 'Tax'
						when 3 then 'Discount'
						when 4 then 'Payment'
						when 5 then 'CashBack'
						when 6 then 'Adjustment'
						when 100 then 'DisplayOnly'
						when 101 then 'InvoiceSummary'
						else '?'
					end as txType
					,(case 
						when rt.TxTypeId= 1 then 
							case
								when rt.IsAccountingCredit = 1 then -rt.Amount 
								else rt.Amount
							end 
						else 0
					end) as SaleAmount
					,(case 
						when rt.TxTypeId= 2 then 
							case
								when rt.IsAccountingCredit = 1 then -rt.Amount 
								else rt.Amount
							end 
						else 0
					end) as TaxAmount
					,(case 
						when rt.TxTypeId= 4 then 
							case
								when rt.IsAccountingCredit = 1 then -rt.Amount 
								else rt.Amount
							end 
						else 0
					end) as PaymentAmount
					,(case 
						when rt.TxTypeId not in (1,2,4) then 
							case
								when rt.IsAccountingCredit = 1 then -rt.Amount 
								else rt.Amount
							end 
						else 0
					end) as OtherAmount
					,rt.Description
				from
					#RawTxTransaction rt
				where 
					isnull(rt.LinkTypeId,0) not in (1,2,3)  -- not caught above
			) rslt
		--WHERE rslt.txtBusinessUnitId = 218--rslt.MemberID =5555754
		order by
			TxInvoiceId
			,txtGroupId
			,TxTransactionID

		--SELECT * FROM #Storage1 s1

		/***********************************************************************************************
		Original resultset
		***********************************************************************************************/
		;with 
			LastEndDate as
				(
				select 
					ROW_NUMBER() over (partition by [SuspensionId] order by [SuspensionEndDateId] desc) as DateNumber
					,*
				from 
					dbo.SuspensionEndDate (nolock))
		select 
			sps.SuspensionId
			,sps.TargetEntityId
			,sps.TargetEntityIdType
			,sps.Status
			,sps.BeginTime
			,led.EndTime
			,CASE sps.[Status] WHEN 0 THEN 'Invalid'
							  WHEN 1 THEN 'Pending Start'
							  WHEN 2 THEN 'Active'
							  WHEN 3 THEN 'Expired'
							  WHEN 4 THEN 'Rescinded'
							  ELSE 'UNKNOWN'
							END AS SuspensionStatus
			,ROW_NUMBER() over (partition by sps.TargetEntityId order by led.EndTime desc) as SuspRN
		into 
			#Suspensions
		from 
			dbo.suspension sps (nolock)
			inner join LastEndDate led on sps.SuspensionId = led.SuspensionId and led.DateNumber=1
		where 
			sps.TargetEntityIdType = 8
			and sps.Status not in (0,4)
			and
			(
					(convert(date,sps.BeginTime,101) between @OriginaBilllingDate and @BillingEndDate)
					or
					(convert(date,led.EndTime,101) between @OriginaBilllingDate and @BillingEndDate)
					or
					(@BillingStartDate between convert(date,sps.BeginTime,101) and convert(date,led.EndTime,101))
					or
					(@BillingEndDate between convert(date,sps.BeginTime,101) and convert(date,led.EndTime,101))
					or
					(@OriginaBilllingDate between convert(date,sps.BeginTime,101) and convert(date,led.EndTime,101))
				)	
			;
	
	--declare @OriginaBilllingDate date;
	--declare @BillingStartDate date;
	--declare @BillingEndDate datetime;

	--SET @OriginaBilllingDate = '4/1/2016'--CONVERT(DATE, GETDATE(), 101)--'9/4/2015'
	--SET @BillingStartDate = '4/1/2016'--CONVERT(DATE, GETDATE(), 101)--'9/4/2015'--
	--SET @BillingEndDate = DATEADD(ss,-1,CONVERT(DATETIME,DATEADD(DAY,1,CONVERT(DATE,GETDATE(),101))))--'9/4/2015 23:59:59'--

	IF (OBJECT_ID('tempdb..#Tran') IS NOT NULL) DROP TABLE #Tran

	SELECT p.PaymentProcessRequestId
			, p.PaymentProcessBatchId
			, p.TxPaymentId
			, t.TxInvoiceId
			, t.TxTransactionID
			, t.TargetDate
			, t.Description
			, t.LinkTypeId
			, t.LinkId
	INTO #Tran
	FROM TxTransaction t
	LEFT JOIN PaymentProcessRequest p ON p.TxPaymentId = t.ItemId
	WHERE CONVERT(DATE,t.TargetDate,101) = CONVERT(DATE,@BillingStartDate,101)
		AND t.TxTypeID = 4
		AND t.LinkTypeID NOT IN (17,20,8)

--	SELECT * FROM #Tran

		SELECT DISTINCT
			--'FULL ' AS ReportType,
			'' AS TransactionsToRemove
			, s1.MemberID
			, s1.MemberAgreementId
			, s1.AgreementStatus
			, s1.AgreementName
			, s1.TxInvoiceId
			, s1.TxTransactionID
			, i.TxPaymentId AS TxPaymentID
			, i.PaymentProcessRequestId AS [MOSOPay-Transaction]
			, s1.TxtGroupID
			, s1.txtBusinessUnitId
			, s1.txtBusinessUnitName
			, s1.mairBillDate
			, s1.txiTargetDate
			, s1.txtTargetDate
			, s1.txiDueDate
			, s1.maprDueDate
			, s1.txType
			, s1.SaleAmount
			, s1.TaxAmount
			, s1.PaymentAmount
			, s1.OtherAmount
			, s1.Description
			, convert(date,c.Date,101) AS CancellationStartDate
			, m.StartDate
			, m.EditableStartDate
			, convert(date,sps.BeginTime,101) as SuspensionStart
			, convert(date,sps.EndTime,101) as SuspensionEnd
		INTO #Final
		FROM #Storage1 s1 
		LEFT JOIN #Tran i ON i.TxInvoiceID = s1.TxInvoiceId
		--LEFT JOIN dbo.PaymentProcessRequest p ON p.TxPaymentId = i.TxPaymentID
		LEFT JOIN dbo.Cancellation c ON c.EntityID = s1.MemberAgreementId AND c.EntityIdType = 1 AND c.StateId != 6
		LEFT JOIN dbo.MemberAgreement m ON m.MemberAgreementId = s1.MemberAgreementId
		LEFT JOIN #Suspensions sps on s1.MemberAgreementId = sps.TargetEntityId
			and sps.SuspRN = 1
		WHERE 1=1
			--and s1.txType = 'Sale'
			--AND s1.TxType != 'Tax'

		GROUP BY 
			 s1.MemberID
			, s1.MemberAgreementId
			, s1.AgreementName
			, s1.AgreementStatus
			, s1.TxInvoiceId
			, s1.TxTransactionID
			, i.TxPaymentId
			, i.PaymentProcessRequestId
			, s1.TxtGroupID
			, s1.txtBusinessUnitId
			, s1.txtBusinessUnitName
			, s1.mairBillDate
			, s1.txiTargetDate
			, s1.txtTargetDate
			, s1.txiDueDate
			, s1.maprDueDate
			, s1.txType
			, s1.SaleAmount
			, s1.TaxAmount
			, s1.PaymentAmount
			, s1.OtherAmount
			, s1.Description
			, c.Date
			, m.StartDate
			, m.EditableStartDate
			, convert(date,sps.BeginTime,101) 
			, convert(date,sps.EndTime,101) 



SELECT 'No PaymentProcessRequestID',* 
FROM #Final b 
WHERE [MOSOPay-Transaction] IS NULL 
	AND txtype = 'Payment' 
	AND Description not like '%Transfer%'
	AND (PaymentAmount > 0 OR PaymentAmount < 0)
	AND TxPaymentId IS NOT NULL
			


--IF(Object_ID('TSI_Tactical.dbo.Staging_WhatBilled_JAN') IS NOt NULL) DROP TABLE TSI_Tactical.dbo.Staging_WhatBilled_JAN

DECLARE @BillingValidation INT = 1,
		@DevCore BIT = 1;


--IF (@DevCore = 0 AND @BillingValidation = 1) 
--	BEGIN
--		SELECT *
--		--INTO TSI_Tactical.dbo.Staging_WhatBilled
--		INTO TSI_Tactical.dbo.Staging_WhatBilled_JAN
--		FROM #Final f


--		SELECT * 
--		FROM TSI_Tactical.dbo.Staging_WhatBilled_JAN
--		--WHERE b.mair


		--->>> BEGIN VALIDATION SCRIPTs
				DECLARE @VAL_BillDate DATE = CONVERT(DATE,GETDATE(),101)

--				SELECT COUNT(*) FROM TSI_Tactical.dbo.Staging_WhatBilled_DEC b 





--	END
--IF (@DevCore = 1 AND @BillingValidation = 1) 
--	BEGIN

--
DROP TABLE TSI_Tactical.dbo.Storage_April_WhatBilled_Final

SELECT * 
INTO TSI_Tactical.dbo.Storage_April_WhatBilled_Final
FROM #Final f

SELECT COUNT(*)
FROM TSI_Tactical.dbo.Storage_april_WhatBilled_Final

SELECT *  
FROM TSI_Tactical.dbo.Storage_april_WhatBilled_Final
WHERE txType = 'Sale'

SELECT * 
FROM TSI_Tactical.dbo.Storage_april_WhatBilled_Final
WHERE txType = 'Payment'


		--->>> BEGIN VALIDATION SCRIPTs
DECLARE @VAL_BillDate DATE = CONVERT(DATE,GETDATE(),101)


SELECT * FROM TSI_Tactical.dbo.Storage_April_WhatBilled_Final b 
WHERE [MOSOPay-Transaction] IS NULL 
		AND TxType = 'Payment'
		AND Description LIKE '%Sponsor%'

SELECT *
FROM PaymentProcessRequest p 
WHERE TxPaymentID= 21743871

SELECT 'Billing Date Not Today',* FROM TSI_Tactical.dbo.Storage_April_WhatBilled_Final b WHERE txtype = 'sale' and mairBillDate != @VAL_BillDate AND mairBillDate != DATEADD(DAY,-1,@VAL_BillDate)

--Expected 0
SELECT 'Payment Due Date Out of Alignment',* FROM TSI_Tactical.dbo.Storage_April_WhatBilled_Final b WHERE mairBillDate != maprDueDate

--
SELECT 'Premier BabySitting',* FROM TSI_Tactical.dbo.Storage_April_WhatBilled_Final b WHERE agreementname like '%Premier Babysitting%' AND txtype = 'sale'ORDER BY MemberID, MemberAgreementId
--2400 aprox No PaymentProcessRequestIDs
SELECT 'No PaymentProcessRequestID',* FROM TSI_Tactical.dbo.Storage_April_WhatBilled_Final b 
		WHERE [MOSOPay-Transaction] IS NULL 
			AND txtype = 'Payment' 
			AND Description not like '%Transfer%'
			AND (PaymentAmount > 0 OR PaymentAmount < 0)
			
SELECT 'MAJOR PROBLEM - Closed BU',* FROM TSI_Tactical.dbo.Storage_April_WhatBilled_Final b WHERE txtBusinessUnitID IN (2,205, 54)

--DECLARE @VAL_BillDate DATE = CONVERT(DATE,GETDATE(),101)

SELECT 'Suspension Not Started Issue'
	, *
FROM TSI_Tactical.dbo.Storage_April_WhatBilled_Final b
WHERE txType = 'Payment'
	AND SuspensionStart <= @Val_BillDate 
	AND SuspensionEnd > @VAL_BillDate
	AND AgreementStatus != 'Freeze'

SELECT 	'Suspension Not Ended Issue'
	, *
FROM TSI_Tactical.dbo.Storage_April_WhatBilled_Final b
WHERE txType = 'Payment'
	AND SuspensionEnd < @VAL_BillDate
	AND AgreementStatus = 'Freeze'

--SELECT * FROM MemberAgreementInvoiceRequest WHERE MemberAgreementID = 3479928
--SELECT * FROM MemberAgreementPaymentRequest mp INNER JOIN MemberAgreementInvoiceRequest mr ON mr.MemberAgreementInvoiceRequestId = mp.MemberAgreementInvoiceRequestId WHERE mr.MemberAgreementID = 3479928
--SELECT * FROM TxInvoice  i INNER JOIN PartyRole p ON I.PartyRoleId = p.PartyRoleId  WHERE RoleId = '8353992'
--SELECT * FROM TSI_TargetedSyncAudit  t WHERE t.MemberAgreementID = 3479928 

--SELECT * FROM #Final WHERE TxType = 'Payment' 

--SELECT 'BackBilled' AS Error, * FROM TSI_Tactical.dbo.Storage_March_WhatBilled_Final WHERE mairBillDate < CONVERT(DATE,GETDATE(),101)  AND txtype = 'sale' AND SaleAmount > 0
--UNION			SELECT 'FREEZE' AS Error,* FROM TSI_Tactical.dbo.Storage_March_WhatBilled_Final WHERE AgreementStatus = 'Freeze' AND SaleAmount > 15 AND txtype = 'sale' AND SaleAmount > 0 AND suspensionstart < CONVERT(DATE,GETDATE(),101) AND SuspensionEnd > CONVERT(DATE,GETDATE(),101)
--UNION			SELECT 'Payment Due Date Out of Alignment' AS Error,* FROM TSI_Tactical.dbo.Storage_March_WHatBilled_Final b WHERE mairBillDate != maprDueDate
--UNION			SELECT 'MAJOR PROBLEM - Closed BU' AS Error,* FROM TSI_Tactical.dbo.Storage_March_WHatBilled_Final b WHERE txtBusinessUnitID IN (2)  AND txtype = 'sale' AND SaleAmount > 0
--UNION			SELECT 'Cancelled Agreement' AS Error, * FROM TSI_Tactical.dbo.Storage_March_WHatBilled_Final b WHERE CancellationStartDate <= CONVERT(DATE,GETDATE(),101) AND SaleAmount > 0
--UNION			SELECT 'No PaymentProcessRequestID' AS Error,f.* FROM TSI_Tactical.dbo.Storage_March_WHatBilled_Final f WHERE [MOSOPay-Transaction] IS NULL AND txtype = 'Payment' AND Description not like '%Transfer%'

--UNION			SELECT 'Premier BabySitting',* FROM TSI_Tactical.dbo.Storage_March_WHatBilled_Final b WHERE agreementname like '%Premier Babysitting%' AND txtype = 'sale' AND SaleAmount > 0

-- SELECT CONCAT('D:\MTP\TSI\Moso.TaskProcessor.exe /tenantIds 204 /SendBatch /businessUnitIds ', BusinessUnitID)  FROM #BUs

					--WHERE TxType = 'Sale'
/*
--SELECT * FROM #Final f
		--->>> BEGIN VALIDATION SCRIPTs
				--DECLARE @VAL_BillDate DATE = CONVERT(DATE,GETDATE(),101)

				--SELECT COUNT(*) FROM #Final b 

				SELECT * FROM TSI_Tactical.dbo.Storage_Feb_WHatBilled_Final

				----SELECT 'Billing Date Not Today',* FROM #Final b WHERE txtype = 'sale' and mairBillDate != @VAL_BillDate AND mairBillDate != DATEADD(DAY,-1,@VAL_BillDate)
				SELECT 'Payment Due Date Out of Alignment',* FROM TSI_Tactical.dbo.Storage_Feb_WHatBilled_Final b WHERE mairBillDate != maprDueDate AND txtype = 'Sale'
				SELECT 'Premier BabySitting',* FROM TSI_Tactical.dbo.Storage_Feb_WHatBilled_Final b WHERE agreementname like '%Premier Babysitting%' AND txtype = 'sale'ORDER BY MemberID, MemberAgreementId
				SELECT 'BackBilling', * FROM TSI_Tactical.dbo.Storage_Feb_WHatBilled_Final --WHERE 
				SELECT 'No PaymentProcessRequestID',f.* FROM #Final f INNER JOIN #BUs b ON f.txtBusinessUnitId = b.BusinessUnitId WHERE [MOSOPay-Transaction] IS NULL AND txtype = 'Payment' AND Description not like '%Transfer%'
				SELECT 'MAJOR PROBLEM - Closed BU',* FROM #Final b WHERE txtBusinessUnitID IN (2)

				--SELECT * FROM PaymentProcessRequest p WHERE LEN(p.Token) < 20 AND p.TransactionDate = CONVERT(DATE, GETDATE(), 101)


	END


/******* SCRAP YARD **************

SELECT *
FROM Txtransaction 
WHERE txInvoiceId = 17269915

SELECT 'No PaymentProcessRequestID',txtBusinessUnitID,txtBusinessUnitName, COUNT(txtBusinessUnitID)
FROM TSI_Tactical.dbo.Staging_WhatBilled_DEC b 
WHERE [MOSOPay-Transaction] IS NULL 
		AND txtype = 'Payment' 
		AND Description not like '%Transfer%'
GROUP BY txtBusinessUnitID,txtBusinessUnitName
ORDER BY 4 DESC

		SELECT DISTINCT txtBusinessUnitID, bu.name
		FROM TSI_Tactical.dbo.Staging_WhatBilled_DEC b 
		INNER JOIN dbo.BusinessUnit bu ON bu.BusinessUnitID = b.txtBusinessUnitID

		SELECT DISTINCT b.Name
				, bu.txtBusinessUnitID
		FROM BusinessUnit b
		LEFT JOIN TSI_Tactical.dbo.Staging_WhatBilled_DEC bu ON bu.txtbusinessUnitID = b.BUsinessUnitID AND bu.txtBusinessUnitID IN (12,13,15,16,17,19,20,21,23,24,25,26,28,29,30,31,32,33,34,38,43,53,54,55,56,59,60,61,62,63,69,70,71,72,73,74,75,76,77,79,80,81,83,84,85,86,93,94,95,96,98,99,105,106,107,110,112,118,120,128,129,130,131,135,138,142,143,144,146,148,149,150,151,152,154,155,156,158,159,160,161,162,163,164,165,166,167,168,169,174,175,179,181,182,184,193,202,203,204,205,206,207,208,227,228,229,230,231,232,235,236,237,238)
		WHERE b.BusinessUnitID IN (12,13,15,16,17,19,20,21,23,24,25,26,28,29,30,31,32,33,34,38,43,53,54,55,56,59,60,61,62,63,69,70,71,72,73,74,75,76,77,79,80,81,83,84,85,86,93,94,95,96,98,99,105,106,107,110,112,118,120,128,129,130,131,135,138,142,143,144,146,148,149,150,151,152,154,155,156,158,159,160,161,162,163,164,165,166,167,168,169,174,175,179,181,182,184,193,202,203,204,205,206,207,208,227,228,229,230,231,232,235,236,237,238)	
			AND bu.txtBusinessUnitID IS NULL

*******/
/*

SELECT *
DELETE
FROM PaymentProcessRequest 
WHERE PaymentProcessRequestID IN (7001082,7001076,7001102,7001094)

*/*/