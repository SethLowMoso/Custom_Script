/*********************************************************************************
Very Simplistic script intended to move an agreement from one businessunit to another. 
********************************************************************************/

UPDATE m SET m.BusinessUnitID = a.[New BUID]
--SELECT m.MemberAgreementID, m.BusinessUnitId, a.MOVETOBU
--SELECT a.MemberID, m.MemberAgreementID, m.BusinessUnitID, a.[New Buid]
FROM TSI_tactical.[dbo].[Storage_NS138911_MemberAgreementMove_WallToFiDi] a
INNER JOIN tenant_TSI.dbo.MemberAgreement m on a.MemberAgreementid = m.MemberAgreementid 
WHERE m.BusinessUnitId = 161

