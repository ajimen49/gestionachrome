# GestionaChrome

Eina senzilla per exportar i importar perfils de Google Chrome entre ordinadors.

Pensada especialment per a docents i usuaris que necessiten traslladar ràpidament:
- Perfils
- Adreces d’interès (preferits)
- Historial
- Imatges de perfil

Sense complicacions tècniques ni configuracions avançades.

---

## 🧩 Què fa exactament?

GestionaChrome permet:

- Exportar perfils seleccionats de Chrome a un fitxer `.zip`.
- Importar aquests perfils en un altre ordinador des d'un fitxer `.zip`
- Recuperar:
  - **✔ Preferits** (adreces d’interès)
  - **✔ Historial de navegació**
  - **✔ Avatars / imatges de perfil**
-Eliminar perfils de Chrome d'una manera àgil i segura.

Evita també problemes habituals:
- **❌ No copia extensions** (evita errors i comportaments estranys).
- **❌ No copia configuracions internes complexes**.
- **✔ Registra correctament els perfils** perquè Chrome els reconegui.

---

## 🚀 Maneres d’utilitzar-lo

Tens dues opcions, segons el teu nivell i preferència:

### 🔹 Opció 1 — Fitxer ZIP (recomanada)

1. Descarrega el `.zip`.
2. Descomprimeix-lo.
3. Executa el fitxer `GestionaChrome.bat`.

Aquest fitxer:
- Executa l’aplicació automàticament.
- Evita bloquejos de PowerShell.
- No requereix configuració prèvia.

👉 És la forma més fàcil i segura.

### 🔹 Opció 2 — Executable (.exe)

Si disposes de la versió `.exe`:

1. Fes doble clic sobre l’executable.
2. Segueix els passos en pantalla.

👉 No requereix PowerShell ni cap configuració addicional.

---

## ⚠️ Avisos importants

És possible que Windows mostri alguns avisos normals durant l’ús:

### "Windows ha protegit el teu PC"
- Clica a **"Més informació"** → **"Executa igualment"**.

### Avisos de PowerShell
- El `.bat` ja aplica automàticament **`ExecutionPolicy Bypass`**.
- No cal fer res manualment.

### Antivirus / SmartScreen
- Pot marcar el fitxer com desconegut.
- Això és normal en eines no signades digitalment.

👉 L’aplicació no instal·la res ni modifica el sistema fora de Chrome.

---

## 🧭 Funcionament bàsic

### Exportar

1. Obre l’aplicació.
2. Selecciona perfils.
3. Marca què vols exportar:
   - **Preferits**
   - **Historial**
4. Genera el fitxer `.zip`.

### Importar

1. Obre l’aplicació.
2. Selecciona el fitxer `.zip`.
3. Tria què vols recuperar.
4. Importa.

👉 Els perfils apareixeran automàticament dins Chrome.

### Eliminar perfils

GestionaChrome també permet eliminar perfils de Google Chrome de manera ràpida i centralitzada.

L'eliminació:
- tanca Chrome automàticament si cal,
- elimina el perfil seleccionat,
- neteja la configuració interna de Chrome,
- evita perfils "fantasma" o duplicats.

---

## ⚙️ Limitacions (importants)

Aquesta eina prioritza l’estabilitat i compatibilitat. Per això:

- **❌ No exporta extensions.**
- **❌ No exporta configuracions internes de Chrome.**
- **❌ Algunes connexions o inici de sessió poden no conservar-se.**

👉 L’objectiu és evitar errors com:
- Extensions trencades.
- Webs que fallen.
- Perfils corruptes.

---

## 🎯 Casos d’ús típics

- Canvi d’ordinador d'un/a docent.
- Preparació d’equips per a una aula.
- Clonació de perfils base.
- Recuperació ràpida de preferits i historial.

---

## 📦 Contingut del ZIP

El paquet inclou:

- **`GestionaChrome.ps1`** → Aplicació principal.
- **`GestionaChrome.bat`** → Llançador automàtic.

El `.bat` executa PowerShell amb permisos suficients per evitar bloquejos habituals.

---

## 📌 Resum

GestionaChrome és una eina:
- Pràctica
- Directa
- Pensada per funcionar sense complicacions

👉 Si busques traslladar perfils i preferits de Chrome fàcilment, aquesta eina està dissenyada exactament per a això.

---

## 🧑‍💻 Desenvolupament

Aquest projecte ha estat ideat i desenvolupat per **ajimen49**.
