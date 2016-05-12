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

	SET @OriginaBilllingDate = '4/30/2016'--CONVERT(DATE, GETDATE(), 101)--'9/4/2015'
	SET @BillingStartDate = '4/30/2016'--CONVERT(DATE, GETDATE(), 101)--'9/4/2015'--
	SET @BillingEndDate = DATEADD(ss,-1,CONVERT(DATETIME,DATEADD(DAY,1,CONVERT(DATE,GETDATE(),101))))--'9/4/2015 23:59:59'--


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
			, txt.[Description]
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
			inner join dbo.StatusMap sm (nolock) on sm.StatusId = ma.[Status]
				and sm.StatusMapType = 5
		where 1=1
			and txt.TargetDate >= @BillingStartDate 
			and txt.TargetDate < @BillingEndDate  -- limit to date range
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

SELECT * 
FROM #Final
--WHERE txtBusinessUnitId IN (108,161)

DECLARE @BillingValidation INT = 1,
		@DevCore BIT = 0,
		@StagingTable INT = 1,
		@CompleteValidation INT = 0,
		@VAL_BillDate DATE = CONVERT(DATE,GETDATE(),101);



		--->>> BEGIN VALIDATION SCRIPTs
IF(@BillingValidation = 1)
	BEGIN
		SELECT COUNT(*) AS RecordCount FROM #Final
		SELECT 'SALE' AS [Type],*  FROM #Final WHERE txType = 'Sale'
		SELECT 'PAYMENT' AS [Type],*  FROM #Final WHERE txType = 'Payment'

		DECLARE @SalesAmount INT = (SELECT SUM(SaleAmount) AS SumOfSales FROM #Final WHERE TxType = 'Sale')
				, @TaxAmmount INT = (SELECT SUM(TaxAmount) AS SumOfTax FROM #Final WHERE TxType = 'Tax')
				, @PaymentAmount INT = (SELECT SUM(PaymentAmount) AS SumOfPayments FROM #Final WHERE TxType = 'Payment')
		SELECT @SalesAmount AS SalesAmount
				, @TaxAmmount AS TaxAmount
				, @SalesAmount + @TaxAmmount AS TotalTransaction
				, @PaymentAmount AS PaymentAmmount

				 

		IF(@StagingTable = 1)
			BEGIN
				IF(OBJECT_ID('TSI_Tactical.dbo.Storage_WhatBilled_May') IS NOT NULL )DROP TABLE TSI_Tactical.dbo.Storage_WhatBilled_May
				
				SELECT  *
				INTO TSI_Tactical.dbo.Storage_WhatBilled_May
				FROM #Final f
			END


		IF(@CompleteValidation = 1)
			BEGIN



				--->>> BEGIN VALIDATION SCRIPTs
				SELECT 'No PaymentProcessRequestID',* 
					FROM #Final b 
					WHERE [MOSOPay-Transaction] IS NULL 
						AND txtype = 'Payment' 
						AND Description not like '%Transfer%'
						AND (PaymentAmount > 0 OR PaymentAmount < 0)
						AND TxPaymentId IS NOT NULL
			


				SELECT 'Sponsor Transfer Payments', * 
						FROM #Final b 
						WHERE [MOSOPay-Transaction] IS NULL 
							AND TxType = 'Payment'
							AND Description LIKE '%Sponsor%'

				--DECLARE @VAL_BillDate DATE = CONVERT(DATE,GETDATE(),101);


				SELECT 'Billing Date Not Today',* 
						FROM #Final b 
						WHERE txtype = 'sale' 
							AND mairBillDate != @VAL_BillDate 
							AND mairBillDate != DATEADD(DAY,-1,@VAL_BillDate)

				--Expected 0
				SELECT 'Payment Due Date Out of Alignment',* 
						FROM #Final b 
						WHERE mairBillDate != maprDueDate

				-- This is getting commented out as it is no longer an anomoly.
				--SELECT 'Premier BabySitting',* FROM #Final b WHERE agreementname like '%Premier Babysitting%' AND txtype = 'sale'ORDER BY MemberID, MemberAgreementId

				--2400 aprox No PaymentProcessRequestIDs
				SELECT 'No PaymentProcessRequestID',* 
						FROM #Final b 
						WHERE [MOSOPay-Transaction] IS NULL 
							AND txtype = 'Payment' 
							AND Description not like '%Transfer%'
							AND (PaymentAmount > 0 OR PaymentAmount < 0)
			
				SELECT 'MAJOR PROBLEM - Closed BU',* FROM #Final b WHERE txtBusinessUnitID IN (2,205, 54)


				--DECLARE @VAL_BillDate DATE = CONVERT(DATE,GETDATE(),101);


				SELECT 'Suspension Not Started Issue', *
						FROM #Final b
						WHERE txType = 'Payment'
							AND SuspensionStart <= @Val_BillDate 
							AND SuspensionEnd > @VAL_BillDate
							AND AgreementStatus != 'Freeze'
							AND [MosoPay-Transaction] IS NOT NULL

				SELECT 	'Suspension Not Ended Issue', *
						FROM #Final b
						WHERE txType = 'Payment'
							AND SuspensionEnd < @VAL_BillDate
							AND AgreementStatus = 'Freeze'



				SELECT *
				INTO TSI_Tactical.dbo.Storage_May_PaymentProcessRequestData_Remmoval
				FROM PaymentProcessRequest p
				WHERE p.PaymentProcessRequestId IN (10116916,10085842,10387337,10192186,10418654,10109660,10108738,10326939,10059436,10496294,10071025,10096973,10134770,10129422,10113794,10116129,10100665,10542895,10546558,10391333,10038035,10112926,10270551,10077057,10080955,10263522,10181970,10064389,10534961,10131323,10190625,10167020,10139906,10026737,10190638,10057912,10097107,10133380,10246911,10076936,10080362,10543391,10069358,10088254,10092562,10537882,10458425,10458413,10192058,10165856,10138277,10138202,10138221,10076604,10523678,10104760,10151135,10123481,10505362,10109277,10207394,10530823,10551092,10530318,10171805,10299970,10511915,10305639,10185359,10542898,10055472,10132770,10398311,10543264,10154331,10189551,10543913,10375313,10266476,10150578,10201845,10550193,10064791,10094925,10050127,10087804,10051485,10070863,10506575,10119533,10271712,10118365,10191075,10078712,10080938,10100276,10108742,10078692,10143257,10152771,10206452,10461584,10337777,10116995,10228037,10323446,10154607,10360535,10401712,10071088,10314014,10314026,10200114,10095642,10182802,10200106,10372797,10504899,10143571,10049036,10475124,10136360,10060236,10094074,10070995,10071008,10548366,10122954,10058148,10113962,10100877,10106944,10126771,10399126,10137767,10173806,10186643,10085988,10267473,10414189,10140182,10094856,10058069,10530067,10371666,10282705,10401207,10331945,10060593,10047022,10259971,10148394,10361952,10121206,10086070,10465262,10536219,10156356,10391769,10402726,10402699,10257686,10079092,10219924,10155528,10530542,10548622,10550377,10135602,10236783,10336559,10116233,10236339,10444819,10067748,10504480,10067735,10173077,10111911,10262247,10254728,10374394,10104925,10551615,10153591,10122911,10021831,10281937,10511235,10529492,10239336,10070628,10483653,10075714,10530626,10541330,10118804,10136904,10078911,10071776,10118529,10497026,10497018,10053874,10502327,10532398,10410043,10117735,10498222,10136199,10246855,10022725,10110559,10332167,10201876,10051475,10037310,10074691,10499262,10154723,10445949,10399547,10171670,10064354,10085214,10478418,10112664,10453474,10082771,10082204,10098696,10076051,10038160,10412777,10083462,10276495,10079048,10095404,10063741,10231254,10547435,10109296,10063756,10134062,10539186,10079149,10308241,10389124,10074212,10024682,10489335,10021589,10023837,10495565,10484463,10075169,10128716,10480265,10060533,10075466,10096580,10122724,10098890,10119148,10150534,10025712,10115301,10498936,10085356,10526868,10210503,10324100,10532611,10428314,10134752,10078713,10166671,10076351,10196422,10363085,10107235,10124851,10134675,10134628,10286518,10094748,10067437,10405381,10048186,10058176,10026977,10049790,10445298,10035494,10137246,10058182,10507449,10020528,10414736,10356910,10131167,10547121,10077492,10252119,10104064,10048071,10134730,10106255,10100129,10498370,10114174,10467494,10297013,10036829,10113379,10160204,10104718,10258582,10166339,10146814,10531548,10512116,10504063,10104503,10138400,10128368,10508850,10413924,10497520,10532175,10199677,10050154,10169329,10221357,10047512,10282696,10259042,10550928,10258947,10145148,10547694,10380935,10091877,10532236,10371350,10128758,10407527,10413029,10551617,10136839,10138199,10135160,10412331,10085470,10079221,10512740,10072582,10164449,10029865,10112309,10283841,10408075,10442539,10031337,10102544,10207281,10035966,10136827,10077575,10117069,10091333,10168125,10065347,10273891,10113654,10443127,10304149,10322792,10311656,10317491,10030139,10476119,10072643,10399994,10098386,10148513,10095838,10023541,10291999,10045065,10454692,10323724,10070554,10193574,10222622,10062950,10401310,10078799,10512656,10412457,10431930,10131270,10070768,10301693,10391123,10394152,10437904,10101586,10454093,10142043,10410991,10039548,10029995,10386400,10548133,10424949,10066732,10386749,10034910,10496907,10023080,10532623,10328525,10094456,10410978,10333492,10121115,10548226,10068054,10068031,10053272,10033962,10491653,10467850,10063246,10401653,10095349,10072525,10097815,10028367,10183835,10288123,10118783,10449598,10442876,10133311,10043962,10335260,10163176,10057193,10476065,10269540,10095506,10349845,10159205,10075486,10078564,10340622,10234289)

				SELECT *
				INTO TSI_Tactical.dbo.Storage_May_WhatBilled_Removal
				FROM #Final
				WHERE [MosoPay-Transaction] IN (10116916,10085842,10387337,10192186,10418654,10109660,10108738,10326939,10059436,10496294,10071025,10096973,10134770,10129422,10113794,10116129,10100665,10542895,10546558,10391333,10038035,10112926,10270551,10077057,10080955,10263522,10181970,10064389,10534961,10131323,10190625,10167020,10139906,10026737,10190638,10057912,10097107,10133380,10246911,10076936,10080362,10543391,10069358,10088254,10092562,10537882,10458425,10458413,10192058,10165856,10138277,10138202,10138221,10076604,10523678,10104760,10151135,10123481,10505362,10109277,10207394,10530823,10551092,10530318,10171805,10299970,10511915,10305639,10185359,10542898,10055472,10132770,10398311,10543264,10154331,10189551,10543913,10375313,10266476,10150578,10201845,10550193,10064791,10094925,10050127,10087804,10051485,10070863,10506575,10119533,10271712,10118365,10191075,10078712,10080938,10100276,10108742,10078692,10143257,10152771,10206452,10461584,10337777,10116995,10228037,10323446,10154607,10360535,10401712,10071088,10314014,10314026,10200114,10095642,10182802,10200106,10372797,10504899,10143571,10049036,10475124,10136360,10060236,10094074,10070995,10071008,10548366,10122954,10058148,10113962,10100877,10106944,10126771,10399126,10137767,10173806,10186643,10085988,10267473,10414189,10140182,10094856,10058069,10530067,10371666,10282705,10401207,10331945,10060593,10047022,10259971,10148394,10361952,10121206,10086070,10465262,10536219,10156356,10391769,10402726,10402699,10257686,10079092,10219924,10155528,10530542,10548622,10550377,10135602,10236783,10336559,10116233,10236339,10444819,10067748,10504480,10067735,10173077,10111911,10262247,10254728,10374394,10104925,10551615,10153591,10122911,10021831,10281937,10511235,10529492,10239336,10070628,10483653,10075714,10530626,10541330,10118804,10136904,10078911,10071776,10118529,10497026,10497018,10053874,10502327,10532398,10410043,10117735,10498222,10136199,10246855,10022725,10110559,10332167,10201876,10051475,10037310,10074691,10499262,10154723,10445949,10399547,10171670,10064354,10085214,10478418,10112664,10453474,10082771,10082204,10098696,10076051,10038160,10412777,10083462,10276495,10079048,10095404,10063741,10231254,10547435,10109296,10063756,10134062,10539186,10079149,10308241,10389124,10074212,10024682,10489335,10021589,10023837,10495565,10484463,10075169,10128716,10480265,10060533,10075466,10096580,10122724,10098890,10119148,10150534,10025712,10115301,10498936,10085356,10526868,10210503,10324100,10532611,10428314,10134752,10078713,10166671,10076351,10196422,10363085,10107235,10124851,10134675,10134628,10286518,10094748,10067437,10405381,10048186,10058176,10026977,10049790,10445298,10035494,10137246,10058182,10507449,10020528,10414736,10356910,10131167,10547121,10077492,10252119,10104064,10048071,10134730,10106255,10100129,10498370,10114174,10467494,10297013,10036829,10113379,10160204,10104718,10258582,10166339,10146814,10531548,10512116,10504063,10104503,10138400,10128368,10508850,10413924,10497520,10532175,10199677,10050154,10169329,10221357,10047512,10282696,10259042,10550928,10258947,10145148,10547694,10380935,10091877,10532236,10371350,10128758,10407527,10413029,10551617,10136839,10138199,10135160,10412331,10085470,10079221,10512740,10072582,10164449,10029865,10112309,10283841,10408075,10442539,10031337,10102544,10207281,10035966,10136827,10077575,10117069,10091333,10168125,10065347,10273891,10113654,10443127,10304149,10322792,10311656,10317491,10030139,10476119,10072643,10399994,10098386,10148513,10095838,10023541,10291999,10045065,10454692,10323724,10070554,10193574,10222622,10062950,10401310,10078799,10512656,10412457,10431930,10131270,10070768,10301693,10391123,10394152,10437904,10101586,10454093,10142043,10410991,10039548,10029995,10386400,10548133,10424949,10066732,10386749,10034910,10496907,10023080,10532623,10328525,10094456,10410978,10333492,10121115,10548226,10068054,10068031,10053272,10033962,10491653,10467850,10063246,10401653,10095349,10072525,10097815,10028367,10183835,10288123,10118783,10449598,10442876,10133311,10043962,10335260,10163176,10057193,10476065,10269540,10095506,10349845,10159205,10075486,10078564,10340622,10234289)


				SELECT *
				FROM TSI_Tactical.dbo.Storage_May_PaymentProcessRequestData_Remmoval

				SELECT *
				FROM TSI_Tactical.dbo.Storage_May_WhatBilled_Removal


				DELETE 
				-- SELECT *
				FROM PaymentProcessRequest 
				WHERE PaymentProcessRequestId IN (10116916,10085842,10387337,10192186,10418654,10109660,10108738,10326939,10059436,10496294,10071025,10096973,10134770,10129422,10113794,10116129,10100665,10542895,10546558,10391333,10038035,10112926,10270551,10077057,10080955,10263522,10181970,10064389,10534961,10131323,10190625,10167020,10139906,10026737,10190638,10057912,10097107,10133380,10246911,10076936,10080362,10543391,10069358,10088254,10092562,10537882,10458425,10458413,10192058,10165856,10138277,10138202,10138221,10076604,10523678,10104760,10151135,10123481,10505362,10109277,10207394,10530823,10551092,10530318,10171805,10299970,10511915,10305639,10185359,10542898,10055472,10132770,10398311,10543264,10154331,10189551,10543913,10375313,10266476,10150578,10201845,10550193,10064791,10094925,10050127,10087804,10051485,10070863,10506575,10119533,10271712,10118365,10191075,10078712,10080938,10100276,10108742,10078692,10143257,10152771,10206452,10461584,10337777,10116995,10228037,10323446,10154607,10360535,10401712,10071088,10314014,10314026,10200114,10095642,10182802,10200106,10372797,10504899,10143571,10049036,10475124,10136360,10060236,10094074,10070995,10071008,10548366,10122954,10058148,10113962,10100877,10106944,10126771,10399126,10137767,10173806,10186643,10085988,10267473,10414189,10140182,10094856,10058069,10530067,10371666,10282705,10401207,10331945,10060593,10047022,10259971,10148394,10361952,10121206,10086070,10465262,10536219,10156356,10391769,10402726,10402699,10257686,10079092,10219924,10155528,10530542,10548622,10550377,10135602,10236783,10336559,10116233,10236339,10444819,10067748,10504480,10067735,10173077,10111911,10262247,10254728,10374394,10104925,10551615,10153591,10122911,10021831,10281937,10511235,10529492,10239336,10070628,10483653,10075714,10530626,10541330,10118804,10136904,10078911,10071776,10118529,10497026,10497018,10053874,10502327,10532398,10410043,10117735,10498222,10136199,10246855,10022725,10110559,10332167,10201876,10051475,10037310,10074691,10499262,10154723,10445949,10399547,10171670,10064354,10085214,10478418,10112664,10453474,10082771,10082204,10098696,10076051,10038160,10412777,10083462,10276495,10079048,10095404,10063741,10231254,10547435,10109296,10063756,10134062,10539186,10079149,10308241,10389124,10074212,10024682,10489335,10021589,10023837,10495565,10484463,10075169,10128716,10480265,10060533,10075466,10096580,10122724,10098890,10119148,10150534,10025712,10115301,10498936,10085356,10526868,10210503,10324100,10532611,10428314,10134752,10078713,10166671,10076351,10196422,10363085,10107235,10124851,10134675,10134628,10286518,10094748,10067437,10405381,10048186,10058176,10026977,10049790,10445298,10035494,10137246,10058182,10507449,10020528,10414736,10356910,10131167,10547121,10077492,10252119,10104064,10048071,10134730,10106255,10100129,10498370,10114174,10467494,10297013,10036829,10113379,10160204,10104718,10258582,10166339,10146814,10531548,10512116,10504063,10104503,10138400,10128368,10508850,10413924,10497520,10532175,10199677,10050154,10169329,10221357,10047512,10282696,10259042,10550928,10258947,10145148,10547694,10380935,10091877,10532236,10371350,10128758,10407527,10413029,10551617,10136839,10138199,10135160,10412331,10085470,10079221,10512740,10072582,10164449,10029865,10112309,10283841,10408075,10442539,10031337,10102544,10207281,10035966,10136827,10077575,10117069,10091333,10168125,10065347,10273891,10113654,10443127,10304149,10322792,10311656,10317491,10030139,10476119,10072643,10399994,10098386,10148513,10095838,10023541,10291999,10045065,10454692,10323724,10070554,10193574,10222622,10062950,10401310,10078799,10512656,10412457,10431930,10131270,10070768,10301693,10391123,10394152,10437904,10101586,10454093,10142043,10410991,10039548,10029995,10386400,10548133,10424949,10066732,10386749,10034910,10496907,10023080,10532623,10328525,10094456,10410978,10333492,10121115,10548226,10068054,10068031,10053272,10033962,10491653,10467850,10063246,10401653,10095349,10072525,10097815,10028367,10183835,10288123,10118783,10449598,10442876,10133311,10043962,10335260,10163176,10057193,10476065,10269540,10095506,10349845,10159205,10075486,10078564,10340622,10234289)

			END


END
