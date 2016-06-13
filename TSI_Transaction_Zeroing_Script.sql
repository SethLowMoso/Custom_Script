--DROP TABLE TSI_Tactical.dbo.Storage_Zeroing_Transactions_ForTSI

DECLARE
	@Date DATE = '6/13/2016'
	, @DELETE_RESET INT = 0
	, @TxInvoiceID INT = NULL
/***********************
1) ID Transactions Transactions to Zero out amount
***********************/

INSERT INTO TSI_Tactical.dbo.Staging_ZERO_TransactionResetAudit
	(RoleID, MPay_TransCode, PPReq_BatchID, PPReq_ID, PPReq_Amount, TxInv_ID, TxTrans_ID, TxTrans_Amount, TxPay_ID, TxPay_Amount)
SELECT r.RoleID AS RoleID
		, pr.PaymentProcessRequestId AS MPay_TransCode
		, pr.PaymentProcessBatchId AS PPReq_BatchID
		, pr.PaymentProcessRequestId AS PPReq_ID
		, pr.TotalAmount AS PPReq_Amount
		, t.TxInvoiceId AS TxInv_ID 
		, t.TxTransactionID AS TxTrans_ID
		, t.Amount AS TxTrans_Amount
		, p.TxPaymentID AS TxPay_ID
		, p.Amount AS TxPay_Amount
FROM dbo.TxTransaction t 
INNER JOIN TxPayment p ON p.TxPaymentID = t.ItemId-- AND CONVERT(Date,p.TargetDate,101) = '6/6/2016'
INNER JOIN PaymentProcessrequest pr ON pr.TxPaymentID = p.TxPaymentID
INNER JOIN PartyRole r ON r.PartyRoleID = p.PartyRoleID
WHERE 1=1
	AND t.TxTypeId = 4
	AND t.ItemID IN (24030504,24027811,24033050,24033046,24030503,24030520,24030495,24045895,24030419,24033052,24030413,24033034,24033036,24039645,24030501,24030497,24033039,24030401,24030288,24048750,24049770,24030525,24049828,24030533,24030493,24033055,24030499,24033041,24030298,24049769,24030509,24049886)
	AND p.TxPaymentID IN (24030504,24027811,24033050,24033046,24030503,24030520,24030495,24045895,24030419,24033052,24030413,24033034,24033036,24039645,24030501,24030497,24033039,24030401,24030288,24048750,24049770,24030525,24049828,24030533,24030493,24033055,24030499,24033041,24030298,24049769,24030509,24049886)
ORDER BY p.Amount DESC





/***********************
2) Update Transactions to Zero out amount
***********************/

UPDATE t SET Amount = 0, t.Comments = 'NS137636 - Clearing the invoice amount'
--SELECT *
FROM TxTransaction t
INNER JOIN TSI_Tactical.dbo.Staging_ZERO_TransactionResetAudit s ON s.TxTrans_ID = t.TxTransactionID
WHERE 1=1
	AND s.Audit_Date = @Date
	AND s.TxInv_ID = IIF(@TxInvoiceID IS NULL, s.TxInv_ID, @TxInvoiceID)

/***********************
3) Update TxPayment to Zero out Amount
***********************/


UPDATE p SET p.Amount = 0
--SELECT p.*
FROM TxPayment p
INNER JOIN TSI_Tactical.dbo.Staging_ZERO_TransactionResetAudit s ON s.TxPay_ID = p.TxPaymentID
WHERE 1=1
	AND s.Audit_Date = @date
	AND s.TxInv_ID = IIF(@TxInvoiceID IS NULL, s.TxInv_ID, @TxInvoiceID)

/***********************
4) Update PaymentProcessRequest to Zero out Amount
***********************/
IF (@DELETE_RESET = 0 )
	BEGIN
		--SELECT p.TotalAmount, p.TaxAmount, p.FeeAmount
		UPDATE p SET p.TotalAmount = 0 , p.TaxAmount = 0 , p.FeeAmount = 0
		FROM PaymentProcessRequest p
		INNER JOIN TSI_Tactical.dbo.Staging_ZERO_TransactionResetAudit s ON s.PPReq_ID = p.PaymentProcessRequestId
		WHERE 1=1
			AND s.Audit_Date = @Date
			AND s.TxInv_ID = IIF(@TxInvoiceID IS NULL, s.TxInv_ID, @TxInvoiceID)
	END

IF (@DELETE_RESET = 1)
	BEGIN
		DELETE
		FROM PaymentProcessRequest 
		WHERE PaymentProcessRequestID IN (SELECT PaymentProcessRequestID
											FROM TSI_Tactical.dbo.Staging_ZERO_TransactionResetAudit 
											WHERE 1=1
												AND Audit_Date = @Date
												AND TxInv_ID = IIF(@TxInvoiceID IS NULL, TxInv_ID, @TxInvoiceID))
		
		UPDATE pb SET pb.RequestSentTime = NULL, pb.RequestSentTime_UTC = NULL, pb.RequestSentTime_ZoneFormat = NULL
		FROM PaymentProcessBatch pb
		WHERE 1=1
			AND CONVERT(DATE,pb.CreationTime,101) = @Date

			
	END 



