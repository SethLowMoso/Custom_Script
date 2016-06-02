--select 
--	ppb.BusinessUnitId
--	,bu.Name
--	,sum(Amount) as Amount
--	,count(*) as Transactions
--	,min(ppb.CreationTime) as CreationTime
--	,max(ppb.CreationTime) as CreationTime
--from
--	dbo.PaymentProcessBatch ppb
--	inner join dbo.PaymentProcessRequest ppr on ppb.PaymentProcessBatchId = ppr.PaymentProcessBatchId
--	inner join dbo.TxPayment txp on ppr.TxPaymentId = txp.TxPaymentID
--	inner join dbo.BusinessUnit bu on ppb.BusinessUnitId = bu.BusinessUnitId
--where 1=1
--	--ppb.RequestSentTime is null
--	and convert(date,ppb.CreationTime) = '3/1/2015'
--	and isnull(txp.LinkTypeId,0) != 2 -- filter out cancellations
--group by
--	ppb.BusinessUnitId
--	,bu.Name
--order by
--	ppb.BusinessUnitId

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DROP TABLE #temp

declare @Now datetime = getdate()
declare @Now1 datetime = dateadd(month,-1,@Now)
declare @Now2 datetime = dateadd(month,-2,@Now)
declare @Now3 datetime = dateadd(month,-3,@Now)
declare @Now4 datetime = dateadd(month,-4,@Now)
declare @Now5 datetime = dateadd(month,-5,@Now)
declare @Now6 datetime = dateadd(month,-6,@Now)


select
	convert(date,@Now4,101) AS BillDate
	,sum(Amount) as Amount
	,count(*) as Transactions
	,min(ppb.CreationTime) as MIN_CreationTime
	,max(ppb.CreationTime) as MAX_CreationTime
INTO #Temp
from
	dbo.PaymentProcessBatch ppb
	inner join dbo.PaymentProcessRequest ppr on ppb.PaymentProcessBatchId = ppr.PaymentProcessBatchId
	inner join dbo.TxPayment txp on ppr.TxPaymentId = txp.TxPaymentID
where 1=1
	--ppb.RequestSentTime is null
	and ppb.CreationTime between convert(date,@Now6) and @Now6
	and isnull(txp.LinkTypeId,0) != 2 -- filter out cancellations

union all 


select
	convert(date,@Now4,101) AS BillDate
	,sum(Amount) as Amount
	,count(*) as Transactions
	,min(ppb.CreationTime) as MIN_CreationTime
	,max(ppb.CreationTime) as MAX_CreationTime
from
	dbo.PaymentProcessBatch ppb
	inner join dbo.PaymentProcessRequest ppr on ppb.PaymentProcessBatchId = ppr.PaymentProcessBatchId
	inner join dbo.TxPayment txp on ppr.TxPaymentId = txp.TxPaymentID
where 1=1
	--ppb.RequestSentTime is null
	and ppb.CreationTime between convert(date,@Now5) and @Now5
	and isnull(txp.LinkTypeId,0) != 2 -- filter out cancellations

union all 

select
	convert(date,@Now4,101) AS BillDate
	,sum(Amount) as Amount
	,count(*) as Transactions
	,min(ppb.CreationTime) as MIN_CreationTime
	,max(ppb.CreationTime) as MAX_CreationTime
from
	dbo.PaymentProcessBatch ppb
	inner join dbo.PaymentProcessRequest ppr on ppb.PaymentProcessBatchId = ppr.PaymentProcessBatchId
	inner join dbo.TxPayment txp on ppr.TxPaymentId = txp.TxPaymentID
where 1=1
	--ppb.RequestSentTime is null
	and ppb.CreationTime between convert(date,@Now4) and @Now4
	and isnull(txp.LinkTypeId,0) != 2 -- filter out cancellations

union all 

select
	convert(date,@Now3,101) AS BillDate
	,sum(Amount) as Amount
	,count(*) as Transactions
	,min(ppb.CreationTime) as MIN_CreationTime
	,max(ppb.CreationTime) as MAX_CreationTime
from
	dbo.PaymentProcessBatch ppb
	inner join dbo.PaymentProcessRequest ppr on ppb.PaymentProcessBatchId = ppr.PaymentProcessBatchId
	inner join dbo.TxPayment txp on ppr.TxPaymentId = txp.TxPaymentID
where 1=1
	--ppb.RequestSentTime is null
	and ppb.CreationTime between convert(date,@Now3) and @Now3
	and isnull(txp.LinkTypeId,0) != 2 -- filter out cancellations

union all 

select
	convert(date,@Now2,101) AS BillDate
	,sum(Amount) as Amount
	,count(*) as Transactions
	,min(ppb.CreationTime) as MIN_CreationTime
	,max(ppb.CreationTime) as MAX_CreationTime
from
	dbo.PaymentProcessBatch ppb
	inner join dbo.PaymentProcessRequest ppr on ppb.PaymentProcessBatchId = ppr.PaymentProcessBatchId
	inner join dbo.TxPayment txp on ppr.TxPaymentId = txp.TxPaymentID
where 1=1
	--ppb.RequestSentTime is null
	and ppb.CreationTime between convert(date,@Now2) and @Now2
	and isnull(txp.LinkTypeId,0) != 2 -- filter out cancellations

union all 

select
	convert(date,@Now1,101) AS BillDate
	,sum(Amount) as Amount
	,count(*) as Transactions
	,min(ppb.CreationTime) as MIN_CreationTime
	,max(ppb.CreationTime) as MAX_CreationTime
from
	dbo.PaymentProcessBatch ppb
	inner join dbo.PaymentProcessRequest ppr on ppb.PaymentProcessBatchId = ppr.PaymentProcessBatchId
	inner join dbo.TxPayment txp on ppr.TxPaymentId = txp.TxPaymentID
where 1=1
	--ppb.RequestSentTime is null
	and ppb.CreationTime between convert(date,@Now1) and @Now1
	and isnull(txp.LinkTypeId,0) != 2 -- filter out cancellations


union all 

select
	convert(date,@Now,101) AS BillDate
	,sum(Amount) as Amount
	,count(*) as Transactions
	,min(ppb.CreationTime) as MIN_CreationTime
	,max(ppb.CreationTime) as MAX_CreationTime
from
	dbo.PaymentProcessBatch ppb
	inner join dbo.PaymentProcessRequest ppr on ppb.PaymentProcessBatchId = ppr.PaymentProcessBatchId
	inner join dbo.TxPayment txp on ppr.TxPaymentId = txp.TxPaymentID
where 1=1
	--ppb.RequestSentTime is null
	and ppb.CreationTime between convert(date,@Now) and @Now
	and isnull(txp.LinkTypeId,0) != 2 -- filter out cancellations


SELECT t.BillDate
		, t.Amount
		, t.Transactions
		, t.MIN_CreationTime
		, t.MAX_CreationTime
		, ((SELECT Transactions FROM #Temp WHERE BILLDate = @Now) / t.Transactions)
FROM #Temp t
