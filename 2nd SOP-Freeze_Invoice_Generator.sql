declare @RunDate date = '6/2/2016' --getdate();

IF (OBJECT_ID('tempdb..#FreezeInvoices') IS NOT NULL) DROP TABLE #FreezeInvoices

IF (OBJECT_ID('tempdb..#Stage') IS NOT NULL) DROP TABLE #Stage

SELECT *
INTO #Stage
FROM [TSI_tactical].[dbo].[Storage_JUNE_Transactions_To_Reverse] r
WHERE r.TxPaymentID != 'NULL' 

;with 
	CTE_TargetAgreements
		AS (
				SELECT mp.TxPaymentId,
						r.[MOSOPay-Transaction] AS PaymentProcessRequesTID-- r.PaymentProcessRequestId
						, mr.MemberAgreementId
				FROM #Stage r ---UPDATE THIS WITH THE PAYMENT PROCESS REQUEST ROW THAT ARE GETTING REVERSED
				INNER JOIN dbo.MemberAgreementPaymentRequest mp ON MP.TxPaymentId = r.TxPaymentID
				INNER JOIN dbo.MemberAgreementInvoiceRequest mr ON mr.MemberAgreementInvoiceRequestId = mp.MemberAgreementInvoiceRequestId
					
			),			
	LastSuspensionEnd as
		(
			select 
				ROW_NUMBER() over (partition by [SuspensionId] order by [SuspensionEndDateId] desc) as LastSuspensionEndRN
				,sed.SuspensionId
				,convert(date,sed.EndTime) EndTime
			from 
				dbo.SuspensionEndDate sed (nolock)
		),
	LastSupension as
		(
			select
				ROW_NUMBER() over (partition by sps.TargetEntityId order by sps.BeginTime desc) as LastSupensionRN
				,sps.TargetEntityId as MemberAgreementId
				,sps.SuspensionId
				,convert(date,sps.BeginTime) as BeginTime
				,spsr.Name
				,spsr.RecurringFeeItemId
			from 
				dbo.Suspension sps (nolock)
				inner join dbo.SuspensionReason spsr (nolock) on sps.SuspensionReasonId = spsr.SuspensionReasonId
			where
				sps.Status in (1,2,3)
				and sps.BeginTime <= @RunDate
				and sps.TargetEntityIdType & 8 = 8
		),
	NextCancel as
		(
			select
				ROW_NUMBER() over (partition by can.EntityId order by can.Date asc) as NextCancellationRN
				,can.EntityId as MemberAgreementId
				,convert(date,can.Date) as CancellationDate
				,can.EnteredDate as CancellationEnteredDate
			from 
				dbo.Cancellation can (nolock)
			where
				can.StateId in (1,2,3,4,5)
				and can.EntityIdType = 1
		),	
	LastBillDate as
		(
			select
				ROW_NUMBER() over (partition by mair.MemberAgreementID order by mair.BillDate desc) as LastBillRN
				,mair.MemberAgreementID
				,convert(date,mair.BillDate,101) as BillDate
				,txi.TargetDate
				,mair.ProcessType
			from 
				dbo.MemberAgreementInvoiceRequest mair (nolock)
				inner join dbo.MemberAgreementInvoiceRequestItem mairi (nolock)on mair.MemberAgreementInvoiceRequestId = mairi.MemberAgreementInvoiceRequestId
				inner join dbo.MemberAgreementItem mai (nolock) on mairi.MemberAgreementItemId = mai.MemberAgreementItemId
					and mai.IsKeyItem = 1
				inner join dbo.TxInvoice txi (nolock) on mair.TxInvoiceId = txi.TxInvoiceID

				--INNER JOIN tsi_tactical.[dbo].[Storage_Feb_Freeze_InvoiceIssue_FINAL] fin (NOLOCK) ON fin.MemberAgreementId = mair.MemberAgreementID
			where 1=1
				and isnull(mair.ProcessType,0) != 1
				and mair.TxInvoiceId is not null
				and convert(date,mair.BillDate) <= @RunDate
		)
select
	bu.Code as LocationCode
	,bu.Name as LocationName
	,pr.RoleID as MemberID
	,ma.MemberAgreementID
	,convert(date,ma.StartDate) as StartDate
	,convert(date,ma.EditableStartDate) as EditableStartDate
	,replace(replace(replace(agr.Description,char(9),''),char(13),''),char(10),'') as AgreementName
	,replace(replace(replace(bun.Name,char(9),''),char(13),''),char(10),'')  as BundleName
	,sm.Name as AgreementStatus
	,maip.Price as KeyItemPrice
	,lbd.BillDate as LastBillDate
	,lbd.ProcessType as LastBillType
	,sch.Name as BillingSchedule
	,lsps.BeginTime as LastSuspensionBegin
	,lspse.EndTime as LastSuspensionEnd
	,lsps.Name as SuspensionReason
	,lsps.RecurringFeeItemId as SuspensionFeeItemID
	,itm.name as SuspensionFeeItem
	,coalesce(ip_bu.Price,ip_div.Price,ip_ent.Price,0) as FreezeFeePrice
	,nc.CancellationDate
	, itm.UPC AS ItemCode
	,@RunDate as AnalysisDate
INTO #FreezeInvoices
from
	dbo.MemberAgreement ma (nolock)
	INNER JOIN CTE_TargetAgreements ta ON ta.MemberAgreementId = ma.MemberAgreementId

	inner join dbo.PartyRole pr (nolock) on ma.PartyRoleId = pr.PartyRoleID	
	inner join dbo.StatusMap sm (nolock) on ma.Status = sm.StatusId 		and sm.StatusMapType = 5
	inner join dbo.Agreement agr (nolock) on ma.AgreementId = agr.AgreementId 
	inner join dbo.BusinessUnit bu (nolock) on ma.BusinessUnitId = bu.BusinessUnitId
	inner join dbo.MemberAgreementItem mai (nolock) on ma.MemberAgreementId = mai.MemberAgreementId 		and mai.IsKeyItem = 1
	inner join dbo.MemberAgreementItemPerpetual maip (nolock) on mai.MemberAgreementItemId = maip.MemberAgreementItemId 		and maip.BillCount is null
	inner join dbo.BillingSchedule bs (nolock) on maip.BillingScheduleId = bs.BillingScheduleId
	left join dbo.Schedule sch (nolock) on bs.ScheduleId = sch.ScheduleId
	left join dbo.Bundle bun (nolock) on mai.BundleId = bun.BundleId
	left join LastBillDate lbd on ma.MemberAgreementId = lbd.MemberAgreementId 		and lbd.LastBillRN = 1
	left join LastSupension lsps on ma.MemberAgreementId = lsps.MemberAgreementId 		and lsps.LastSupensionRN=1
	left join LastSuspensionEnd lspse on lsps.SuspensionId = lspse.SuspensionId 		and lspse.LastSuspensionEndRN=1
	left join NextCancel nc on ma.MemberAgreementId = nc.MemberAgreementId 		and nc.NextCancellationRN=1
	left join dbo.Item itm (nolock) on lsps.RecurringFeeItemId = itm.ItemID 	
	left join dbo.ItemPrice ip_bu (nolock) on lsps.RecurringFeeItemId = ip_bu.ItemID
		and ip_bu.SourceID = bu.BusinessUnitId
		and ip_bu.SourceLevel = 3
		and @RunDate between ip_bu.StartDate_UTC and isnull(ip_bu.EndDate_UTC,@RunDate)
	left join dbo.ItemPrice ip_div (nolock) on lsps.RecurringFeeItemId = ip_div.ItemID
		and ip_div.SourceID = bu.DivisionId
		and ip_div.SourceLevel = 2
		and @RunDate between ip_div.StartDate_UTC and isnull(ip_div.EndDate_UTC,@RunDate)
	left join dbo.ItemPrice ip_ent (nolock)  on lsps.RecurringFeeItemId = ip_ent.ItemID
		and ip_ent.SourceID = 0
		and ip_ent.SourceLevel = 1
		and @RunDate between ip_ent.StartDate_UTC and isnull(ip_ent.EndDate_UTC,@RunDate)

where 1=1
	and agr.AgreementTypeId = 1  -- Memberships Only
	and pr.PartyRoleTypeID = 1 -- Members Only
	and lsps.SuspensionId is not null -- there was a suspension in effect during date being analyzed
	and isnull(lspse.EndTime,dateadd(day,1,@RunDate)) >= dateadd(day,1,@RunDate) -- the end date of the suspension is past the billing date being analyzed
	and ((nc.CancellationDate is null) or (convert(date,nc.CancellationDate) > @RunDate))  -- if agreement was to be cancelled, it was after the date being analyzed
	and coalesce(ip_bu.Price,ip_div.Price,ip_ent.Price,0) != 0 -- There is a freeze fee assigned
	and lbd.BillDate <= @RunDate -- The last bill date is prior to the analysis date
	--and lbd.BillDate >= @RunDate -- The last bill date on the analysis date
	
	--and sch.Name = 'Monthly on 1st'  -- we are only concerned about memberships billing on the first




-->>> THIS WILL GENERATE THE INVOICES TO IMPORT FILE
SELECT 
		'' AS InvoiceID
		, MemberID AS OwnerID
		, 'Primary Account' AS AccountName
		, SuspensionFeeItem AS ItemName
		, 1 AS Quantity
		, FreezeFeePrice AS Price
		, 'On Account' AS TenderTypeName
		, '' AS GiftCardNumber
		, '' ActivityExpirationDate
		, 'Freeze Fee' InvoiceComment
		, ItemCode
		, LocationCode
		, 1 AS Sequence
FROM #FreezeInvoices


/*

SELECT '' AS InvoiceId
		, a.MemberID AS OwnerID
		, 'Primary Account' AS AccountName
		, SuspensionFeeItemName AS ItemName
		, 1 AS Quantity
		, FeePriceConfig
		, 'On Account' AS TenderTypename
		, '' AS GiftCardNumber
		, '' AS ActivityExpirationDate
		, 'Freeze Fee' AS InvoiceComment
		, i.UPC AS ItemCode
		, b.Code AS LocationCode
		, 1 AS [Sequence]
FROM TSI_Tactical.dbo.Storage_March_SuspensionReversal a
LEFT JOIN Tenant_TSI.dbo.Item i (NOLOCK) ON i.ItemID = a.SuspensionFeeItemID
LEFT JOIN Tenant_TSI.dbo.BusinessUnit b (NOLOCK) ON b.BusinessUnitId = a.BusinessUnitId
--WHERE a.MemberID = '38929'
*/


