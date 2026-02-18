SKP guidelines

Zeer klein (1–3 SKP)
	•	Label change (tekst, kleur, enum value) → 1 SKP
	•	Config value aanpassen (env var, feature flag) → 2 SKP
	•	Kleine FE copy wijziging (geen logica) → 2 SKP
	•	Comment / logging toevoegen → 1 SKP

Klein (5–10 SKP)
	•	Eenvoudige FE aanpassing (component aanpassen, geen state) → 5 SKP
	•	Eenvoudige BE wijziging (condition, mapping) → 5 SKP
	•	Eenvoudige Liquibase change (kolom toevoegen, default) → 8 SKP
	•	Validatie toevoegen (FE of BE) → 8 SKP
	•	Test toevoegen aan bestaande feature → 5 SKP

Middel (15–25 SKP)
	•	Simpele CRUD (nieuwe platte entity, FE + BE, geen relaties) → 20 SKP
	•	Uitbreiding bestaande entity (nieuwe relatie of veld met impact) → 15 SKP
	•	FE component met state + API koppeling → 20 SKP
	•	Kleine refactor (1 module, geen gedragswijziging) → 15 SKP
	•	Performance optimalisatie met meetbaar effect → 25 SKP

Groot (30–50 SKP)
	•	Change per repository (substantieel, niet triviaal) → 30 SKP
	•	Nieuwe API endpoint (incl auth, validatie, tests) → 30 SKP
	•	Complexere Liquibase run (migratie met data) → 25 SKP
	•	Koppeling met bestaand extern systeem → 40 SKP
	•	Setup nieuwe installatie / service → 50 SKP

Zeer groot (60–100 SKP)
	•	Nieuwe module binnen bestaande applicatie → 60 SKP
	•	Nieuwe integratie extern systeem (onbekend domein) → 80 SKP
	•	Grote refactor over meerdere modules → 70 SKP
	•	Security gevoelige wijziging (auth flows, permissions) → 60 SKP


