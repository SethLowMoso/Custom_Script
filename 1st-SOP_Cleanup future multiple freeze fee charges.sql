declare @WITH_UPDATE int = 0;

if (object_id('tempdb..#MultiMAISRI') is not null) drop table #MultiMAISRI;
if (object_id('tempdb..#MAISRItoDelete') is not null) drop table #MAISRItoDelete;
if (object_id('tempdb..#MAPSRItoDelete') is not null) drop table #MAPSRItoDelete;

-- Find all unpaid invoice requests that are for a suspension that have more than one fee item configured
select
	mair.MemberAgreementId
	,maisri.MemberAgreementInvoiceRequestId
	,pr.RoleID
	,count(*) as MAISRIRows
	,max(maisri.MemberAgreementInvoiceSuspensionRequestItemId) LastMAISRI
into
	#MultiMAISRI
from
	dbo.MemberAgreementInvoiceRequest mair
	inner join dbo.MemberAgreementInvoiceSuspensionRequestItem maisri on mair.MemberAgreementInvoiceRequestId = maisri.MemberAgreementInvoiceRequestId
	inner join dbo.MemberAgreement ma on mair.MemberAgreementId = ma.MemberAgreementId
	inner join dbo.PartyRole pr on ma.PartyRoleId = pr.PartyRoleID
where 
	isnull(mair.ProcessType,0) = 4  -- only MAIR records flagged for freeze fee
	and mair.TxInvoiceId is null -- unpaid
group by
	mair.MemberAgreementId
	,maisri.MemberAgreementInvoiceRequestId
	,pr.RoleID
having
	count(*) > 1

select
	maisri.*
into
	#MAISRItoDelete
from
	#MultiMAISRI mm
	inner join dbo.MemberAgreementInvoiceSuspensionRequestItem maisri on mm.MemberAgreementInvoiceRequestId = maisri.MemberAgreementInvoiceRequestId
		and mm.LastMAISRI != maisri.MemberAgreementInvoiceSuspensionRequestItemId
where
	maisri.TxTransactionId is null  -- double check on the unpaid

select
	mapsri.*
into
	#MAPSRItoDelete
from	
	#MAISRItoDelete maisri
	inner join dbo.MemberAgreementPaymentSuspensionRequestItem mapsri on mapsri.MemberAgreementInvoiceSuspensionRequestItemId = maisri.MemberAgreementInvoiceSuspensionRequestItemId



if(@WITH_UPDATE = 1)
	begin
		print 'Update Mode!';

		--backup the data
		IF OBJECT_ID ('tsi_tactical.dbo.MemberAgreementPaymentSuspensionRequestItem_To_Remove') IS NULL
			BEGIN
				select * 
				into tsi_tactical.dbo.MemberAgreementPaymentSuspensionRequestItem_To_Remove 
				from #MAPSRItoDelete
			END
		ELSE
			BEGIN
				INSERT INTO tsi_tactical.dbo.MemberAgreementPaymentSuspensionRequestItem_To_Remove 
				SELECT * 
				FROM #MAPSRItoDelete
			END

		--backup the data
		IF OBJECT_ID ('tsi_tactical.dbo.MemberAgreementInvoiceSuspensionRequestItem_To_Remove') IS NULL
			BEGIN
				select * 
				into tsi_tactical.dbo.MemberAgreementInvoiceSuspensionRequestItem_To_Remove 
				from #MAISRItoDelete
			END
		ELSE
			BEGIN
				INSERT INTO tsi_tactical.dbo.MemberAgreementInvoiceSuspensionRequestItem_To_Remove 
				SELECT * 
				FROM #MAISRItoDelete
			END
		
		-- delete the data
		delete
		from dbo.MemberAgreementInvoiceSuspensionRequestItem 
		where MemberAgreementInvoiceSuspensionRequestItemId in (select MemberAgreementInvoiceSuspensionRequestItemId from #MAISRItoDelete)
		end

else
	begin
		print 'Test Mode!';	

		select * from #MultiMAISRI
		select * from #MAISRItoDelete
		select * from #MAPSRItoDelete
	end


