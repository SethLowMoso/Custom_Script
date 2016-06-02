/*********************************************************************************
Very Simplistic script intended to move an agreement from one businessunit to another. 
********************************************************************************/

UPDATE m SET m.BusinessUnitID = a.MoveToBU
--SELECT m.MemberAgreementID, m.BusinessUnitId, a.MOVETOBU
FROM TSI_tactical.dbo.Storage_NS132542_SoHo_AgreementMoves a
INNER JOIN MemberAgreement m on a.MemberAgreementid = m.MemberAgreementid 
WHERE m.BusinessUnitId = 145
	AND m.PartyRoleID = a.PARTYROLEID
