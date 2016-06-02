/****************************************************************************************************************
-->>> This script is being used to target specific agreements and run sync against them. 
Also to record the Agreements in the Sync Audit Table
****************************************************************************************************************/
if (object_id('tempdb..#Storage1') is not null) drop table #Storage1;

--SELECT * FROM StatusMap s WHERE s.StatusMapType = 5

/**************************************************  FOR TARGETING SPECIFIC BusinessUnits *************************************/
select 
 ppb.BusinessUnitId
 ,bu.Name
 ,sum(Amount) as Amount
 ,count(*) as Transaxtions
 ,max(ppb.CreationTime) as CreationTime
 ,max(ppb.RequestSentTime) as SentTime
 INTO #Storage1
from
 dbo.PaymentProcessBatch ppb
 inner join dbo.PaymentProcessRequest ppr on ppb.PaymentProcessBatchId = ppr.PaymentProcessBatchId
 inner join dbo.TxPayment txp on ppr.TxPaymentId = txp.TxPaymentID
 inner join dbo.BusinessUnit bu on ppb.BusinessUnitId = bu.BusinessUnitId
where 1=1
 --ppb.RequestSentTime is null
 and ppb.CreationTime >= '6/1/2016'
 and isnull(txp.LinkTypeId,0) != 2 -- filter out cancellations
group by
 ppb.BusinessUnitId
 ,bu.Name
having 
 max(ppb.CreationTime) <= dateadd(minute,-120,getdate())
order by
 bu.Name

 /**********************************************************************
 **********************************************************************/

 SELECT CONCAT('D:\MTP\TSI\Moso.TaskProcessor.exe /tenantIds 204 /sendbatch /businessUnitIds ', BusinessUnitID)
 FROM #Storage1

