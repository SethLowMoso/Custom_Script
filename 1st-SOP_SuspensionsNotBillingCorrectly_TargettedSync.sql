/****************************************************************************************************************
-->>> This script is being used to target specific agreements and run sync against them. 
Also to record the Agreements in the Sync Audit Table
****************************************************************************************************************/
if (object_id('tempdb..#Storage1') is not null) drop table #Storage1;

DECLARE @Update INT = 1,
		@Invoicefile INT = 0

		;
	


--SELECT * FROM StatusMap s WHERE s.StatusMapType = 5
/**************************************************  FOR TARGETING SPECIFIC AGREEMENTS *************************************/
set transaction isolation level read uncommitted

declare @CheckDate date = DATEADD(d, 1, EOMONTH(current_timestamp)) --getdate();
-->>> THIS SECTION IDENTIFIES THE PROBLEM AGREEMENTS THAT WILL NEED TO BE SYNC'd
if (object_id('tempdb..#SuspendedAgreements') is not null) drop table #SuspendedAgreements;

;

;with 
	LastSuspensionEnd as
		(
			select 
				ROW_NUMBER() over (partition by [SuspensionId] order by [SuspensionEndDateId] desc) as LastSuspensionEndRN
				,sed.SuspensionId
				,sed.EndTime
			from 
				dbo.SuspensionEndDate sed (nolock)
		)
select 
	ma.MemberAgreementId
	, sps.SuspensionId
	,sps.BeginTime
	,lspse.EndTime
	,spsr.Name as SuspensionReason
	,itm.Name as RecurringFeeItem
	,coalesce(ip_bu.Price,ip_div.Price,ip_ent.Price,0) as FeeAmount
into
	#SuspendedAgreements
from
	dbo.Suspension sps 
	inner join LastSuspensionEnd lspse on sps.SuspensionId = lspse.SuspensionId
		and lspse.LastSuspensionEndRN=1
	inner join dbo.MemberAgreement ma on sps.TargetEntityId = ma.MemberAgreementId
	inner join dbo.BusinessUnit bu on ma.BusinessUnitId = bu.BusinessUnitId
	inner join dbo.SuspensionReason spsr on sps.SuspensionReasonId = spsr.SuspensionReasonId
	left join dbo.Item itm on sps.RecurringFeeItemId = itm.ItemID
	left join dbo.ItemPrice ip_bu on sps.RecurringFeeItemId = ip_bu.ItemID
		and ip_bu.SourceID = bu.BusinessUnitId
		and ip_bu.SourceLevel = 3
		and @CheckDate between ip_bu.StartDate_UTC and isnull(ip_bu.EndDate_UTC,@CheckDate)
	left join dbo.ItemPrice ip_div on sps.RecurringFeeItemId = ip_div.ItemID
		and ip_div.SourceID = bu.DivisionId
		and ip_div.SourceLevel = 2
		and @CheckDate between ip_div.StartDate_UTC and isnull(ip_div.EndDate_UTC,@CheckDate)
	left join dbo.ItemPrice ip_ent on sps.RecurringFeeItemId = ip_ent.ItemID
		and ip_ent.SourceID = 0
		and ip_ent.SourceLevel = 1
		and @CheckDate between ip_ent.StartDate_UTC and isnull(ip_ent.EndDate_UTC,@CheckDate)
where 
	1=1
	and sps.TargetEntityIdType = 8
	and sps.Status in (1,2,3,5)
	and @CheckDate >= convert(date,sps.BeginTime,101) 
	and @CheckDate < convert(date,lspse.EndTime,101)
	and ma.Status != 7 -- Cancelled
	and sps.RecurringFeeItemId is not null
	--and ma.MemberAgreementId = 2123252
	and coalesce(ip_bu.Price,ip_div.Price,ip_ent.Price,0) != 0


;with 
	LastBillDate as
		(
			select
				ROW_NUMBER() over (partition by mair.MemberAgreementID order by mair.BillDate desc) as LastBillRN
				,mair.MemberAgreementID
				,convert(date,mair.BillDate,101) as BillDate
				,txi.TargetDate
			from 
				dbo.MemberAgreementInvoiceRequest mair (nolock)
				inner join dbo.MemberAgreementInvoiceRequestItem mairi (nolock)on mair.MemberAgreementInvoiceRequestId = mairi.MemberAgreementInvoiceRequestId
				inner join dbo.MemberAgreementItem mai (nolock) on mairi.MemberAgreementItemId = mai.MemberAgreementItemId
					and mai.IsKeyItem = 1
				inner join dbo.TxInvoice txi (nolock) on mair.TxInvoiceId = txi.TxInvoiceID
			where 1=1
				and isnull(mair.ProcessType,0) != 1
				and mair.TxInvoiceId is not null
				and mair.BillDate < @CheckDate
		),
	NextBillDate as
		(
			select
				ROW_NUMBER() over (partition by mair.MemberAgreementID order by mair.BillDate asc) as NextBillRN
				,mair.MemberAgreementID
				,convert(date,mair.BillDate,101) as BillDate
				,isnull(mair.ProcessType,0) as NBDProcessType
			from 
				dbo.MemberAgreementInvoiceRequest mair (nolock)
				inner join dbo.MemberAgreementInvoiceSuspensionRequestItem maisri on mair.MemberAgreementInvoiceRequestId = maisri.MemberAgreementInvoiceRequestId
			where 1=1
				and isnull(mair.ProcessType,0) != 0
				and mair.TxInvoiceId is null
				and mair.BillDate >= @CheckDate
		),
	NextCancel as
		(
			select
				ROW_NUMBER() over (partition by can.EntityId order by can.Date asc) as NextCancellationRN
				,can.EntityId as MemberAgreementId
				,can.Date as CancellationDate
				,can.EnteredDate as CancellationEnteredDate
			from 
				dbo.Cancellation can (nolock)
			where
				can.StateId in (1,2,3,4,5)
				and can.EntityIdType = 1
		)
select
	bu.Code as LocationCode
	,bu.Name as LocationName
	,bu.BusinessUnitId
	,pr.RoleID as MemberID
	,ma.MemberAgreementID
	,ma.StartDate
	,ma.EditableStartDate
	,replace(replace(replace(agr.Description,char(9),''),char(13),''),char(10),'') as AgreementName
	,replace(replace(replace(bun.Name,char(9),''),char(13),''),char(10),'')  as BundleName
	,sm.Name as AgreementStatus
	,maip.Price as KeyItemPrice
	,lbd.BillDate as LastBillDate
	,nbd.BillDate as NextBillDate
	,nbd.NBDProcessType
	, sa.SuspensionId
	,sa.RecurringFeeItem
	,sa.FeeAmount
	,sa.BeginTime as SuspensionBegin
	,sa.EndTime as SuspensionEnd
	,nc.CancellationDate
	,@CheckDate as CheckDate
INTO #Storage1 --TSI_Tactical.dbo.Storage_NS_Suspension_Not_Billing
from
	#SuspendedAgreements sa
	inner join dbo.MemberAgreement ma (nolock) on sa.MemberAgreementId = ma.MemberAgreementId
	inner join dbo.PartyRole pr (nolock) on ma.PartyRoleId = pr.PartyRoleID	
	inner join dbo.StatusMap sm (nolock) on ma.Status = sm.StatusId
		and sm.StatusMapType = 5
	inner join dbo.Agreement agr (nolock) on ma.AgreementId = agr.AgreementId
	inner join dbo.BusinessUnit bu (nolock) on ma.BusinessUnitId = bu.BusinessUnitId
	inner join dbo.MemberAgreementItem mai (nolock) on ma.MemberAgreementId = mai.MemberAgreementId
		and mai.IsKeyItem = 1
	inner join dbo.MemberAgreementItemPerpetual maip (nolock) on mai.MemberAgreementItemId = maip.MemberAgreementItemId
		and maip.BillCount is null
	inner join dbo.Bundle bun (nolock) on mai.BundleId = bun.BundleId
	left join LastBillDate lbd on sa.MemberAgreementId = lbd.MemberAgreementId
		and lbd.LastBillRN = 1
	left join NextBillDate nbd on sa.MemberAgreementId = nbd.MemberAgreementId
		and nbd.NextBillRN = 1
	left join NextCancel nc on sa.MemberAgreementId = nc.MemberAgreementId
		and nc.NextCancellationRN = 1
where 1=1
	and pr.PartyRoleTypeID=1
	and isnull(nbd.NBDProcessType,0) != 4
	and isnull(nc.CancellationDate,@CheckDate) >= @CheckDate


--->>> GENERATE THE INVOICE FILE IF NEEDED
---->>>> THIS SECTION NEEDS WORK AND WON'T FUNCTION AT PRESENT
--IF (@InvoiceFile = 1)
--	BEGIN
--		SELECT 
--		'' AS InvoiceID
--		, MemberID AS OwnerID
--		, 'Primary Account' AS AccountName
--		, SuspensionFeeItem AS ItemName
--		, 1 AS Quantity
--		, FreezeFeePrice AS Price
--		, 'On Account' AS TenderTypeName
--		, '' AS GiftCardNumber
--		, '' ActivityExpirationDate
--		, 'Freeze Fee' InvoiceComment
--		, ItemCode
--		, LocationCode
--		, 1 AS Sequence
--		FROM #Storage1

--	END

--->>> GIVE BACK THE RESULTS OF THE SEARCH
IF (@Update = 0)
	BEGIN

		SELECT COUNT(*) 
		FROM #Storage1 s
		
		SELECT * 
		FROM #Storage1 s
		LEFT JOIN  [Tenant_TSI].[dbo].[CachedIsValidForSync] c on s.memberagreementid = c.memberagreementid
		WHERE c.MemberAgreementId is null

		

	END

--->>> GENERATING THE SYNC COMMANDS
IF (@Update = 1)
	BEGIN
		--SELECT COUNT(*) FROM TSI_Tactical.dbo.Storage_NS_Suspension_Not_Billing
		/***********************************************************************************************
		AUDIT _ Using this to track what agreements are getting synced by this process
		***********************************************************************************************/
		/*
		INSERT INTO TSI_TargetedSyncAudit 
			(Audit_Reason, RoleID, MemberAgreementID, AgreementStatus, BusinessUnitID, SuspensionID, CancellationID, Notes)
		SELECT 
				 'Freeze Cleanup' AS Audit_Reason
				, ba.MemberID
				, ba.MemberAgreementId
				, ba.AgreementStatus
				, ba.BusinessUnitId
				, ba.SuspensionId
				, NULL as CancellationID
				, 'Atlas suspension cleanup. This should trigger the Sync schedule to clean up these agreements.' AS Notes
		FROM #Storage1 ba
		*/

		--insert into tenant_TSI.dbo.CachedIsValidForSync 
		--SELECT DISTINCT s.MemberAgreementId AS MemberAgreementID
		--		, s.SuspensionId AS SuspensionID
		--		, su.Status AS SuspensionStatus
		--		, s.SuspensionBegin AS BeginTime
		--		, s.SuspensionEnd AS EndTime
		--		, GETDATE() AS ValidDate
		--FROM #Storage1 s
		--LEFT JOIN Tenant_TSI.dbo.Suspension su ON su.SuspensionId = s.SuspensionId
		--LEFT JOIN  [Tenant_TSI].[dbo].[CachedIsValidForSync] c on s.memberagreementid = c.memberagreementid
		--WHERE c.MemberAgreementId is null
			


--SELECT * FROM tenant_TSI.dbo.CachedIsValidForSync v WHERE v.MemberAgreementId = 1038325





		/***********************************************************************************************/

		
		if (object_id('tempdb..#Results') is not null) drop table #Results

		Declare @businessUnitIds INT
			, @memberAgreementId INT
			, @memAgrInvReqId INT
			, @tmpBUid INT = 0 
			, @agrs nvarchar(max)
			, @tenantId varchar(100) = 204;


		-- MTP commands generation to group by business unit -- 
		CREATE TABLE #Results (
				MTPCommand VARCHAR(MAX)
			)

		declare chk cursor for 
		select distinct BusinessUnitId, MemberAgreementId
		from #Storage1 ba


		open chk
		fetch chk into @businessUnitIds, @memberAgreementId

		while @@FETCH_STATUS <>-1
		begin
			if (@tmpBUid != @businessUnitIds and @agrs IS NOT NULL)
			begin
				INSERT INTO #Results
				select concat ( 'D:\MTP\TSI\Moso.TaskProcessor.exe /tenantIds ', @tenantId ,' /cleanBeforeSync /syncSchedule /businessUnitIds ' , ltrim(str(@tmpBUid)) , ' /memAgrIds "' , @agrs,'"')
				set @agrs = NULL
			end 

			set @tmpBUid = @businessUnitIds
	
			if (@tmpBUid = @businessUnitIds)
			begin
				if (len(@agrs + ltrim(str(@memberAgreementId))) > 2000)
				begin
					INSERT INTO #Results
					select concat ( 'D:\MTP\TSI\Moso.TaskProcessor.exe /tenantIds ', @tenantId ,' /cleanBeforeSync /syncSchedule /businessUnitIds ' , ltrim(str(@tmpBUid)) , ' /memAgrIds "' , @agrs,'"')
					set @agrs = NULL
				end
			
				set @agrs = case when @agrs IS NULL then ltrim(str(@memberAgreementId)) else @agrs + ',' + ltrim(str(@memberAgreementId)) end
			end

			fetch chk into @businessUnitIds, @memberAgreementId
		end
		if @agrs is not null
		INSERT INTO #Results
		select concat ( 'D:\MTP\TSI\Moso.TaskProcessor.exe /tenantIds ', @tenantId ,' /cleanBeforeSync /syncSchedule /businessUnitIds ' , ltrim(str(@tmpBUid)) , ' /memAgrIds "' , @agrs,'"')
		
		close chk
		deallocate chk


		SELECT *
		FROM #Results
		
	END