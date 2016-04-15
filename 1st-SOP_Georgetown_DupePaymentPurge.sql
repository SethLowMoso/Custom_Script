/*************************************************************************************************
This is designed to look for multiple payment requests against the same invoice requests set 
one month apart over the span of one month. It should search for all invoice requests from the 1st
to the last day of the month and see if there is a second Paymentrequest for the same invoicerequest
sometime in the future.
*************************************************************************************************/
IF (object_id('tempdb..#Storage1') IS NOT null) DROP TABLE #Storage1

DECLARE @Update INT = 1
	--->>> This first of the next month
		, @StartDate DATE = DATEADD(d, 1, EOMONTH(current_timestamp)) --'2/1/2016' 
	--->>> This is the 1st of the following month
		, @EndDate DATE = DATEADD(m,1,DATEADD(d, 1, EOMONTH(current_timestamp))) --DATEADD(M, 2, DATEADD(month, DATEDIFF(month, 0, GETDATE()), 0)) --->>'12/1/2015'

--->>> Targetting Date Sample
--SELECT DATEADD(d, 1, EOMONTH(current_timestamp)),DATEADD(m,1,DATEADD(d, 1, EOMONTH(current_timestamp)))

--->>> Create target group

SELECT	p.RoleID
		, pr.[3] AS Firstname
		, pr.[5] AS Lastname 
		, mi.MemberAgreementId
		, ma.Status
		, mi.MemberAgreementInvoiceRequestId
		, mi.Billdate
		, mr.MemberAgreementPaymentRequestId AS mr_PayReqID
		, mr.DueDate AS mr_DueDate
		, mr.TxPaymentID AS mr_TxPaymentID
		, mr2.MemberAgreementPaymentRequestID AS mr2_PayReqID
		, mr2.DueDate AS mr2_DueDate
		, mr2.TxPaymentId AS mr2_TxPaymentID
		--, t1.TxInvoiceID AS MR_TxInvoice
		--, t2.TxInvoiceID AS MR2_TxInvoice
		--, mi.TxInvoiceId AS MI_TxInvoiceID
INTO #Storage1
--SELECT COUNT(*)
FROM MemberAgreementInvoiceRequest mi
INNER JOIN dbo.MemberAgreementPaymentRequest mr ON mi.MemberAgreementInvoiceRequestid = mr.MemberAgreementInvoiceRequestID
INNER JOIN dbo.MemberAgreementPaymentRequest mr2 ON mr2.MemberAgreementInvoiceRequestID = mi.MemberAgreementInvoiceRequestID
LEFT JOIN dbo.MemberAgreement ma (NOLOCK) ON ma.MemberAgreementId = mi.MemberAgreementId
LEFT JOIN dbo.PartyRole p (NOLOCK) ON p.PartyRoleID = ma.PartyRoleID 
LEFT JOIN dbo.PartyPropertiesReporting pr ON pr.PartyId = p.PartyID
WHERE 1=1
--	AND mi.MemberAgreementId = 3278735
	AND mr.MemberAgreementPaymentRequestID != mr2.MemberAgreementpaymentRequestID
	AND mr.DueDate < mr2.DueDate
	--AND mr2.TxPaymentID IS NULL
	AND ISNULL(mi.ProcessType,0) != 1
	AND ISNULL(mr.ProcessType,0) != 1
	AND ISNULL(mr2.ProcessType,0) != 1
	AND ma.Status != 7 
	/****************************************************
	Below will filter to a targeted month. 
	****************************************************/
	AND CONVERT(DATE,mr.DueDate,101) >= @StartDate
	AND CONVERT(DATE,mr.DueDate,101) <=  @EndDate
	AND CONVERT(DATE,mi.BillDate,101) >= @StartDate
	AND CONVERT(DATE,mi.BillDate,101) < @EndDate

ORDER BY p.RoleId DESC

IF (@Update = 0)
	BEGIN
		SELECT * FROM #Storage1
	END

IF (@Update = 1)
	BEGIN
		--->>> Backup Deleted records
		IF (object_id('TSI_Tactical.dbo.Proj_Georgetown_MPR_Backup') IS null)
			BEGIN
				SELECT mpr.*
				INTO TSI_Tactical.dbo.Proj_Georgetown_MPR_Backup
				FROM MemberAgreementPaymentRequest mpr
				INNER JOIN #Storage1 s1 ON s1.mr2_PayReqID = mpr.MemberAgreementPaymentRequestId
			END
		IF (object_id('TSI_Tactical.dbo.Proj_Georgetown_MPR_Backup') IS NOT null)
			BEGIN
				INSERT INTO TSI_Tactical.dbo.Proj_Georgetown_MPR_Backup
					(MemberAgreementPaymentRequestId, ObjectId, MemberAgreementInvoiceRequestId, TxPaymentId, DueDate, DueDate_ZoneFormat, Status, Comments, DueDate_UTC, PrimaryTxPaymentId, ProcessType)
				SELECT mpr.*
				FROM MemberAgreementPaymentRequest mpr
				INNER JOIN #Storage1 s1 ON s1.mr2_PayReqID = mpr.MemberAgreementPaymentRequestId
			END

		--->> Delete records
		DELETE mpr
		--SELECT CONVERT(DATE,mpr.DueDate,101), s1.RoleID, s1.firstname, s1.lastname, s1.MemberAgreementID
		FROM MemberAgreementPaymentRequest mpr
		INNER JOIN TSI_Tactical.dbo.Proj_Georgetown_MPR_Backup mb ON mb.MemberAgreementPaymentrequestID = mpr.MemberAgreementPaymentRequestID
	END

