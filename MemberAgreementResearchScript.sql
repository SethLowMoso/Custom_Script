/*
Member Agreement Research query

*/
DECLARE @MemAgr INT = 1482625,
		@BillDate Date = '5/1/2016'

SELECT p.RoleID
		, pv.[First Name] 
		, pv.[Last Name]
		, b.Name AS BusinessUnit
		, b.BusinessUnitId
		, a.Name AS Agreement
		, m.MemberAgreementID	
		, sm.Name AS AgreementStatus
		, m.StartDate AS AgreementStartDate
		, c.CancellationId
		, c.Date AS CancelDate
		, s.BeginTime 
		, es.EndTime
		, mir.BillDate
		, i.TxInvoiceID
		, t3.Description
		, t.ItemId AS TxPaymentId 
		, t.Amount AS AmountofPayment
		, ir.BillDate AS Last_BillDate
		, ir.TxInvoiceId AS Last_InvoiceID
		, t4.Description AS Last_Description
		, t2.ItemId AS Last_PaymentId
		, t2.Amount AS Last_Amount
FROM MemberAgreement m (NOLOCK)
INNER JOIN StatusMap sm (NOLOCK) ON sm.StatusId = m.Status AND sm.StatusMapType = 5
OUTER APPLY 
	(SELECT MAX(SuspensionID) AS SuspensionID
		FROM Suspension ss  (NOLOCK)
		WHERE ss.TargetEntityId = m.MemberAgreementId
		) MS
LEFT JOIN Suspension s (NOLOCK) ON s.SuspensionId = ms.SuspensionID
OUTER APPLY
	(SELECT MAX(SuspensionEndDateID) AS SuspensionEndDateID
		FROM SuspensionEndDate sed  (NOLOCK)
		WHERE sed.SuspensionId = s.SuspensionId) SE
LEFT JOIN SuspensionEndDate es (NOLOCK) ON es.SuspensionEndDateId = se.SuspensionEndDateID
LEFT JOIN PartyRole p (NOLOCK) ON p.PartyRoleId = m.PartyRoleId
LEFT JOIN Agreement a (NOLOCK) ON a.AgreementId = m.AgreementID
LEFT JOIN MemberAgreementInvoiceRequest mir (NOLOCK) ON mir.MemberAgreementId = m.MemberAgreementId AND CONVERT(DATE,mir.BillDate,101) = IIF(@BillDate IS NOT NULL, @BillDate, mir.BillDate)
LEFT JOIN Cancellation c (NOLOCK) ON c.EntityId = m.MemberAgreementId
OUTER APPLY 
	(SELECT MAX(MemberAgreementInvoiceRequestID) AS LastRequest
		FROM MemberAgreementInvoiceRequest r (NOLOCK)
		WHERE r.MemberAgreementId = m.MemberAgreementId) lmr
LEFT JOIN MemberAgreementInvoiceRequest ir (NOLOCK) ON ir.MemberAgreementInvoiceRequestId = lmr.LastRequest
LEFT JOIN TxInvoice i (NOLOCK) ON i.TxInvoiceId = mir.TxInvoiceId
LEFT JOIN TxTransaction t (NOLOCK) ON t.TxInvoiceId = i.TxInvoiceID AND t.TxTypeId = 4
LEFT JOIN TxTransaction t3 (NOLOCK) ON t3.TxInvoiceId = i.TxInvoiceId AND t3.TxTypeId = 1
LEFT JOIN TxInvoice i2 (NOLOCK) ON i2.TxInvoiceId = ir.TxInvoiceId
LEFT JOIN TxTransaction t2 (NOLOCK) ON t2.TxInvoiceId = i2.TxInvoiceID AND t2.TxTypeID = 4
LEFT JOIN TxTransaction t4 (NOLOCK) ON t4.TxInvoiceId = i2.TxInvoiceId AND t4.TxTypeId = 1
LEFT JOIN PartyPropertiesReportingView pv (NOLOCK) ON pv.PartyId = p.PartyID
LEFT JOIN BusinessUnit b (NOLOCK) ON b.BusinessUnitId = m.BusinessUnitId
WHERE m.MemberAgreementID = @MemAgr
ORDER BY BillDate DESC


/*
Failed List
1043331 --No Billdate or InvoiceID
1055989 --No Billdate or InvoiceID
1056146 --Billdate and InvoiceID, this billed as normal, the Suspension expired prior to billing therefor the agreement billed.
1482380 --No InvoiceID
1482541 --No invoiceid
1482625 --No Billdate or InvoiceID
*/
