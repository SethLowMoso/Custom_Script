/************************************************************************************************************************
This query is designed to find agreements that have a billdate on a certain day and then a duedate that doesn't match the bill 
************************************************************************************************************************/

DECLARE @StartDate DATE = DATEADD(d, 1, EOMONTH(current_timestamp)) --'2/1/2016'
		,@EndDate DATE = DATEADD(m,1,DATEADD(d, 1, EOMONTH(current_timestamp))) --'3/1/2016'
		,@Update INT = 1;
--DROP TABLE TSI_Tactical.dbo.Storage_NS122524_BillDate_VS_DueDate_Mismatch

IF(Object_ID('tempdb..#Staging1') IS NOT NULL) DROP TABLE #Staging1;

--->>> This will show any that have been created since the last run, including ones on the Storage table that for some reason didn't get corrected
SELECT p.RoleID
		, r.[3] AS Firstname
		, r.[5] AS Lastname
		, m.MemberAgreementID 
		, a.Name AS Agreement
		, i.TxInvoiceID
		, i.PaymentDueDate AS InvoiceDueDate
		, mr.MemberAgreementInvoiceRequestID
		, mr.BillDate
		, mr.BillDate_UTC
		, mr.BillDate_ZoneFormat
		, mp.MemberAgreementPaymentRequestID
		, mp.DueDate
		, mp.DueDate_UTC
		, mp.DueDate_ZoneFormat
		, GETDATE() AS Audit_Date
		, 0 AS Completed_IND
INTO #Staging1
FROM MemberAgreementInvoiceRequest mr (NOLOCK) 
INNER JOIN dbo.MemberAgreementPaymentRequest mp (NOLOCK) ON mp.MemberAgreementInvoiceRequestID = mr.memberagreementInvoiceRequestID
LEFT JOIN dbo.MemberAgreement m (NOLOCK) ON m.MemberAgreementID = mr.MemberAgreementID
LEFT JOIN dbo.PartyRole p (NOLOCK) ON p.PartyRoleID = m.PartyRoleID 
LEFT JOIN dbo.Agreement a (NOLOCK) ON a.AgreementID = m.AgreementID
LEFT JOIN dbo.PartyPropertiesReporting r (NOLOCK) ON r.PartyID = p.PartyID
LEFT JOIN dbo.TxInvoice i (NOLOCK) ON i.TxInvoiceId = mr.TxInvoiceId
WHERE 1=1
	AND CONVERT(DATE,mr.Billdate,101) >= @Startdate
	AND CONVERT(DATE,mr.Billdate,101) < @EndDate
	AND CONVERT(DATE,mp.DueDate,101) != CONVERT(DATE,mr.BillDate,101)
	AND ISNULL(mr.ProcessType,0) != 1
GROUP BY p.RoleID
		, r.[3]
		, r.[5]
		, i.TxInvoiceID
		, i.PaymentDueDate
		, m.MemberAgreementID 
		, a.Name
		, mr.MemberAgreementInvoiceRequestID
		, mr.BillDate
		, mr.BillDate_UTC
		, mr.BillDate_ZoneFormat
		, mp.MemberAgreementPaymentRequestID
		, mp.DueDate
		, mp.DueDate_UTC
		, mp.DueDate_ZoneFormat
ORDER BY mr.BillDate DESC


IF (@Update = 0)
	BEGIN 
		
		SELECT *
		FROM #Staging1

	END

IF (@Update = 1)
	BEGIN

		INSERT INTO TSI_Tactical.dbo.Storage_NS122524_BillDate_VS_DueDate_Mismatch
		 (RoleID, Firstname, Lastname, MemberAgreementID, Agreement, MemberAgreementInvoiceRequestID, BillDate, BillDate_UTC, BillDate_ZoneFormat, MemberAgreementPaymentRequestID, DueDate, DueDate_UTC, DueDate_ZoneFormat, Audit_Date, Completed_IND)
		SELECT 
				RoleID
				, Firstname
				, Lastname
				, MemberAgreementID
				, Agreement
				, MemberAgreementInvoiceRequestID
				, BillDate
				, BillDate_UTC
				, BillDate_ZoneFormat
				, MemberAgreementPaymentRequestID
				, DueDate
				, DueDate_UTC
				, DueDate_ZoneFormat
				, Audit_Date
				, Completed_IND
		FROM #Staging1

		--->>> This updates MemberAgreementPaymentRequest with the corrected DueDate
		UPDATE mpr 
		SET mpr.DueDate = bd.BillDate
			, mpr.DueDate_UTC = BD.BillDate_UTC
			, mpr.DueDate_ZoneFormat = BD.BillDate_ZoneFormat
		FROM TSI_Tactical.dbo.Storage_NS122524_BillDate_vs_DueDate_Mismatch bd (NOLOCK)
		INNER JOIN dbo.MemberAgreementPaymentRequest mpr (NOLOCK) ON mpr.MemberAgreementPaymentRequestID = bd.MemberAgreementPaymentRequestID AND mpr.MemberAgreementInvoiceRequestId = bd.MemberAgreementInvoiceRequestID
		WHERE bd.Completed_IND = 0

		--->>> This will update TxInvoice with the corrected PaymentDueDate
		UPDATE i 
		SET i.PaymentDueDate = bd.DueDate
			, i.PaymentDueDate_UTC = bd.DueDate_UTC
			, i.PaymentDueDate_ZoneFormat = bd.DueDate_ZoneFormat
		FROM TxInvoice i (NOLOCK)
		INNER JOIN MemberAgreementInvoiceRequest mr (NOLOCK) ON mr.TxInvoiceId = i.TxInvoiceID
		INNER JOIN TSI_Tactical.dbo.Storage_NS122524_BillDate_vs_DueDate_Mismatch bd (NOLOCK) ON bd.MemberAgreementInvoiceRequestID = mr.MemberAgreementInvoiceRequestId
		WHERE bd.Completed_IND = 0

		--->>> This marks the record as Completed on the staging table so it won't get targetted again.
		UPDATE bd SET bd.Completed_IND = 1
		FROM TSI_Tactical.dbo.Storage_NS122524_BillDate_vs_DueDate_Mismatch bd (NOLOCK) 
		WHERE bd.Completed_IND = 0
	END

IF (@Update = 2)
	BEGIN
		
		--->>> This will only clean up the invoice displaying the correct date. It doesn't touch anything else. 
		UPDATE i 
		SET i.PaymentDueDate = b.BillDate
			, i.PaymentDueDate_UTC = b.BillDate_UTC
			, i.PaymentDueDate_ZoneFormat = b.BillDate_ZoneFormat
		--SELECT p.RoleID, i.TxInvoiceID, i.PaymentDueDate, b.BillDate, mp.DueDate
			FROM [TSI_tactical].[dbo].[Storage_NS122524_BillDate_VS_DueDate_Mismatch] b
			INNER JOIN dbo.MemberAgreementInvoiceRequest mr (NOLOCK) ON mr.MemberAgreementInvoiceRequestId = b.MemberAgreementInvoiceRequestID
			INNER JOIN dbo.TxInvoice i (NOLOCK) ON i.TxinvoiceId = mr.TxInvoiceID 
			INNER JOIN dbo.MemberAgreementPaymentRequest mp (NOLOCK) ON mp.MemberAgreementInvoiceRequestId = mr.MemberAgreementInvoiceRequestId
			INNER JOIN dbo.PartyRole p (NOLOCK) ON p.PartyRoleId = i.PartyRoleID
			WHERE 1=1
			AND i.PaymentDueDate != mp.DueDate
			--AND b.RoleID = 8313175
	END


	/* SCRAP YARD
			--SELECT p.RoleID
		--		, r.[3] AS Firstname
		--		, r.[5] AS Lastname
		--		, m.MemberAgreementID 
		--		, a.Name AS Agreement
		--		, mr.MemberAgreementInvoiceRequestID
		--		, mr.BillDate
		--		, mr.BillDate_UTC
		--		, mr.BillDate_ZoneFormat
		--		, mp.MemberAgreementPaymentRequestID
		--		, mp.DueDate
		--		, mp.DueDate_UTC
		--		, mp.DueDate_ZoneFormat
		--		, GETDATE() AS Audit_Date
		--		, 0 AS Completed_IND
		----INTO TSI_Tactical.dbo.Storage_NS122524_BillDate_VS_DueDate_Mismatch
		--FROM MemberAgreementInvoiceRequest mr (NOLOCK) 
		--INNER JOIN dbo.MemberAgreementPaymentRequest mp (NOLOCK) ON mp.MemberAgreementInvoiceRequestID = mr.memberagreementInvoiceRequestID
		--LEFT JOIN dbo.MemberAgreement m (NOLOCK) ON m.MemberAgreementID = mr.MemberAgreementID
		--LEFT JOIN dbo.PartyRole p (NOLOCK) ON p.PartyRoleID = m.PartyRoleID 
		--LEFT JOIN dbo.Agreement a (NOLOCK) ON a.AgreementID = m.AgreementID
		--LEFT JOIN dbo.PartyPropertiesReporting r (NOLOCK) ON r.PartyID = p.PartyID
		--WHERE 1=1
		--	AND CONVERT(DATE,mr.Billdate,101) >= @Startdate
		--	AND CONVERT(DATE,mr.Billdate,101) < @EndDate
		--	AND CONVERT(DATE,mp.DueDate,101) != CONVERT(DATE,mr.BillDate,101)--DATEADD(MONTH,1,mr.BillDate)
		--	AND ISNULL(mr.ProcessType,0) != 1
		--	--AND mr.MemberAgreementInvoiceRequestID NOT IN (SELECT MemberAgreementInvoiceRequestID FROM TSI_Tactical.dbo.Storage_NS122524_BillDate_VS_DueDate_Mismatch)
		--GROUP BY p.RoleID
		--		, r.[3]
		--		, r.[5]
		--		, m.MemberAgreementID 
		--		, a.Name
		--		, mr.MemberAgreementInvoiceRequestID
		--		, mr.BillDate
		--		, mr.BillDate_UTC
		--		, mr.BillDate_ZoneFormat
		--		, mp.MemberAgreementPaymentRequestID
		--		, mp.DueDate
		--		, mp.DueDate_UTC
		--		, mp.DueDate_ZoneFormat
		--ORDER BY mr.BillDate DE
	*/