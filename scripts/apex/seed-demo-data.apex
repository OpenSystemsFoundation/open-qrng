// QuantumFair demo data seeder — for screenshots, demos and UI development.
//
// Mocks the IBM Quantum API: it builds SamplerV2-shaped result payloads
// locally and feeds them through the REAL completion pipeline
// (JobProcessor.processSamplerCompletion → debiasing → validation →
// certificate + hash chain → assignment engine → extended validation).
// No callouts are made. The bits are NOT quantum — certificates created by
// this script carry "[DEMO]" in their Purpose and must never be used for a
// real assignment.
//
// Usage (one job per run, to stay inside synchronous CPU limits):
//   sf apex run --target-org qrng-dev --file scripts/apex/seed-demo-data.apex
// Edit the SCENARIO index below (0..4) before each run, or use
// scripts/seed-demo-data.sh which runs every scenario in order.

Integer SCENARIO = 0; // replaced by scripts/seed-demo-data.sh

// ── Org setup (idempotent) ────────────────────────────────────────────────
Quantum_Settings__c s = Quantum_Settings__c.getOrgDefaults();
if (String.isBlank(s.IBM_API_Key__c)) {
    s.IBM_API_Key__c = 'demo-key-not-a-real-credential';
    s.Instance_CRN__c = 'crn:v1:bluemix:public:quantum-computing:us-east:a/demo0000000000000000000000000000:demo0000-0000-0000-0000-000000000000::';
    s.Default_Backend__c = 'ibm_fez';
    s.Default_Shots__c = 4096;
    s.Use_Least_Busy__c = true;
    upsert s;
}
List<Quantum_Provider__c> provs = [SELECT Id FROM Quantum_Provider__c WHERE Provider_Key__c = 'ibm' LIMIT 1];
Quantum_Provider__c prov;
if (provs.isEmpty()) {
    prov = new Quantum_Provider__c(Name = 'IBM Quantum', Provider_Key__c = 'ibm',
        Provider_Class__c = 'IBMQuantumService', Auth_Endpoint__c = 'https://iam.cloud.ibm.com/identity/token',
        API_Base_URL__c = 'https://quantum.cloud.ibm.com/api', Is_Active__c = true, Status__c = 'Connected',
        Last_Synced__c = DateTime.now());
    insert prov;
    List<Quantum_Backend__c> bks = new List<Quantum_Backend__c>();
    List<String> names = new List<String>{ 'ibm_fez', 'ibm_marrakesh', 'ibm_kingston' };
    List<Integer> queues = new List<Integer>{ 3, 11, 6 };
    List<String> rev = new List<String>{ '2', '2', '2' };
    List<Integer> qubits = new List<Integer>{ 156, 156, 156 };
    for (Integer i = 0; i < names.size(); i++) {
        bks.add(new Quantum_Backend__c(Name = names[i], Backend_Key__c = 'ibm:' + names[i], Provider__c = prov.Id,
            Status__c = 'online', Num_Qubits__c = qubits[i], Queue_Length__c = queues[i], Is_Simulator__c = false,
            Processor_Family__c = 'Heron', Processor_Revision__c = rev[i], Max_Shots__c = 100000,
            Median_Gate_Error__c = 0.0021 + i * 0.0003, Median_Readout_Error__c = 0.011 + i * 0.002,
            Avg_T1_us__c = 182 - i * 9, Avg_T2_us__c = 121 - i * 7,
            Noise_Source_Type__c = 'Superconducting transmon qubits — projective measurement of |+⟩ states',
            Conditioning_Component__c = 'Per-qubit von Neumann debiasing',
            Last_Calibration__c = DateTime.now().addHours(-3 - i), Last_Synced__c = DateTime.now()));
    }
    insert bks;
    // ibm_fez passed a separate CHSH backend-verification run earlier
    // (Operations → Verify), so certificates issued on it carry that evidence.
    bks[0].put('CHSH_S_Value__c', 2.712);
    bks[0].put('CHSH_Verified_At__c', DateTime.now().addDays(-3));
    update bks[0];
}

// ── Demo business records (idempotent) ────────────────────────────────────
if ([SELECT COUNT() FROM Lead WHERE LeadSource = 'QuantumFair Demo'] == 0) {
    List<String> first = new List<String>{ 'Ava','Noah','Mia','Liam','Zoe','Ethan','Isla','Lucas','Nora','Mason','Leah','Owen','Ruby','Elias','Ivy','Felix','Sara','Hugo','Lena','Theo','Maya','Jonas','Emma','Sam' };
    List<String> co = new List<String>{ 'Northwind','Contoso','Fabrikam','Tailspin','Litware','Adatum','Proseware','Wingtip' };
    List<Lead> leads = new List<Lead>();
    for (Integer i = 0; i < first.size(); i++) {
        leads.add(new Lead(FirstName = first[i], LastName = 'Demo', Company = co[Math.mod(i, co.size())] + ' ' + (i + 1),
            LeadSource = 'QuantumFair Demo', Status = 'Open - Not Contacted'));
    }
    insert leads;
    List<Account> accts = new List<Account>();
    for (Integer i = 1; i <= 30; i++) {
        accts.add(new Account(Name = 'Loan File ' + String.valueOf(1000 + i), AccountNumber = 'QF-DEMO'));
    }
    insert accts;
}
if ([SELECT COUNT() FROM Group WHERE Type = 'Queue' AND DeveloperName LIKE 'QF_Demo_%'] == 0) {
    List<Group> qs = new List<Group>();
    for (String n : new List<String>{ 'EMEA', 'North_America', 'APAC', 'LATAM' }) {
        qs.add(new Group(Name = n.replace('_', ' ') + ' Sales', DeveloperName = 'QF_Demo_' + n, Type = 'Queue'));
    }
    insert qs;
}

// ── Scenario definition ───────────────────────────────────────────────────
List<String> leadIds = new List<String>();
for (Lead l : [SELECT Id FROM Lead WHERE LeadSource = 'QuantumFair Demo' ORDER BY Company]) { leadIds.add(l.Id); }
List<String> acctIds = new List<String>();
for (Account a : [SELECT Id FROM Account WHERE AccountNumber = 'QF-DEMO' ORDER BY Name]) { acctIds.add(a.Id); }
List<String> queueIds = new List<String>();
for (Group g : [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName LIKE 'QF_Demo_%' ORDER BY DeveloperName]) { queueIds.add(g.Id); }

String purpose; String aType; Integer nQubits; Integer shots; Boolean bell = false; String backend; String finalStatus = 'Completed';
QuantumRandomAssignment.AssignmentRequestData req = new QuantumRandomAssignment.AssignmentRequestData();
Integer hoursAgo;
if (SCENARIO == 0) {
    purpose = '[DEMO] Inbound lead distribution — November week 2'; aType = 'Uniform'; nQubits = 12; shots = 4096; backend = 'ibm_fez'; hoursAgo = 50;
    req.recordIds = leadIds; req.assigneeIds = queueIds;
} else if (SCENARIO == 1) {
    purpose = '[DEMO] Regulatory audit sample — Q3 loan files'; aType = 'Subset'; nQubits = 12; shots = 4096; backend = 'ibm_marrakesh'; hoursAgo = 30;
    req.recordIds = acctIds; req.sampleSize = 6;
} else if (SCENARIO == 2) {
    purpose = '[DEMO] Territory rebalancing — weighted by team capacity'; aType = 'Weighted'; nQubits = 12; shots = 4096; backend = 'ibm_kingston'; hoursAgo = 20;
    req.recordIds = leadIds; req.assigneeIds = queueIds; req.weights = new List<Double>{ 0.4, 0.3, 0.2, 0.1 };
} else if (SCENARIO == 3) {
    purpose = '[DEMO] Employee incentive lottery — Bell-verified'; aType = 'Subset'; nQubits = 16; shots = 2048; bell = true; backend = 'ibm_fez'; hoursAgo = 4;
    req.recordIds = leadIds; req.sampleSize = 3;
} else {
    purpose = '[DEMO] Case routing — support tier 2'; aType = 'Uniform'; nQubits = 12; shots = 4096; backend = 'ibm_marrakesh'; hoursAgo = 0;
    req.recordIds = leadIds; req.assigneeIds = queueIds; finalStatus = 'Running';
}
req.assignmentType = aType;
req.purpose = purpose;

// Realistic IBM job id: 20 lowercase alphanumerics starting with 'd'
String alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
String ibmId = 'd';
for (Integer i = 0; i < 19; i++) {
    Integer r = Math.mod(Math.abs(Crypto.getRandomInteger()), alphabet.length());
    ibmId += alphabet.substring(r, r + 1);
}

DateTime submitted = DateTime.now().addHours(-hoursAgo).addMinutes(-17);
// Several job fields are internal (no FLS grant by design — the app writes
// them in system mode), so they are set dynamically here.
Quantum_Job__c job = new Quantum_Job__c();
Map<String, Object> jobFields = new Map<String, Object>{
    'Status__c' => 'Running', 'Purpose__c' => purpose, 'Backend__c' => backend,
    'Num_Qubits__c' => nQubits, 'Shots__c' => shots, 'Use_Bell_Test__c' => bell,
    'Job_Type__c' => 'Quantum', 'Program_Id__c' => 'sampler', 'External_Job_ID__c' => ibmId,
    'Provider__c' => 'ibm', 'Requested_By__c' => UserInfo.getUserId(), 'Submitted_At__c' => submitted,
    'Circuit_QASM__c' => bell ? CircuitBuilder.buildBellTestCircuit(nQubits / 2) : CircuitBuilder.buildStandardCircuit(nQubits),
    'Assignment_Type__c' => aType, 'Assignment_Request__c' => JSON.serialize(req),
    'Poll_Count__c' => finalStatus == 'Running' ? 4 : 9, 'Last_Polled_At__c' => DateTime.now().addMinutes(-2)
};
for (String f : jobFields.keySet()) {
    job.put(f, jobFields.get(f));
}
insert job;
if (finalStatus == 'Running') {
    // Start the background jobs the way the app does after a settings save
    try { SetupController.startSweeper(); } catch (Exception e) { System.debug('sweeper: ' + e.getMessage()); }
    try { SetupController.startIntegrityCheck(); } catch (Exception e) { System.debug('integrity: ' + e.getMessage()); }
    System.debug('Seeded running job ' + job.Id);
    return;
}

// ── Mock IBM SamplerV2 result payload ─────────────────────────────────────
List<String> HEX = new List<String>{ '0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f' };
List<String> samples = new List<String>();
if (!bell) {
    // Uniform bits: 12 qubits = 3 hex digits per shot
    String pool = '';
    while (pool.length() < shots * 3) {
        pool += EncodingUtil.convertToHex(Crypto.generateAesKey(256));
    }
    for (Integer i = 0; i < shots; i++) {
        String h = pool.substring(i * 3, i * 3 + 3).replaceFirst('^0+(?!$)', '');
        samples.add('0x' + h);
    }
} else {
    // Entangled pairs with hardware-like correlators |E| ≈ 0.66 per CHSH config
    // (S ≈ 2.64). Circuit order is (A0,B0,A1,B1,...); IBM strings are reversed.
    List<Double> targetE = new List<Double>{ 0.66, 0.66, 0.66, -0.66 };
    Integer pairs = nQubits / 2;
    for (Integer sIdx = 0; sIdx < shots; sIdx++) {
        List<Integer> bitsCircuitOrder = new List<Integer>();
        for (Integer p = 0; p < pairs; p++) {
            Integer a = Math.random() < 0.5 ? 0 : 1;
            Double pSame = (1 + targetE[Math.mod(p, 4)]) / 2;
            Integer b = Math.random() < pSame ? a : 1 - a;
            bitsCircuitOrder.add(a); bitsCircuitOrder.add(b);
        }
        // IBM order: reverse; then pack to hex (MSB first)
        Integer v = 0;
        for (Integer k = bitsCircuitOrder.size() - 1; k >= 0; k--) {
            v = v * 2 + bitsCircuitOrder[k];
        }
        String h = '';
        do { h = HEX[Math.mod(v, 16)] + h; v = v / 16; } while (v > 0);
        samples.add('0x' + h);
    }
}
Map<String, Object> meas = new Map<String, Object>{ 'samples' => samples, 'num_bits' => nQubits };
Map<String, Object> result0 = new Map<String, Object>{ 'data' => new Map<String, Object>{ 'meas' => meas }, 'metadata' => new Map<String, Object>{ 'circuit_metadata' => new Map<String, Object>() } };
String resultsJson = JSON.serialize(new Map<String, Object>{ 'results' => new List<Object>{ result0 }, 'metadata' => new Map<String, Object>{ 'version' => 2 } });

DateTime runStart = submitted.addMinutes(11);
Map<String, Object> statusResponse = new Map<String, Object>{
    'id' => ibmId, 'status' => 'Completed', 'backend' => backend,
    'timestamps' => new Map<String, Object>{
        'created' => submitted.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''),
        'running' => runStart.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''),
        'finished' => runStart.addSeconds(6).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'')
    },
    'usage' => new Map<String, Object>{ 'quantum_seconds' => bell ? 4 : 3, 'seconds' => bell ? 4 : 3 }
};

JobProcessor.ProcessingResult r = JobProcessor.processSamplerCompletion(job, resultsJson, statusResponse);
// Backdate completion so the dashboard timeline looks like a real history
Quantum_Job__c done = new Quantum_Job__c(Id = job.Id);
done.put('Completed_At__c', runStart.addSeconds(6));
done.put('Execution_Time_ms__c', 6000);
update done;
System.debug('Seeded job ' + job.Id + ' status=' + r.status + ' cert=' + r.certificateId + ' rawBits=' + r.rawBitsLength + ' debiased=' + r.debiasedBitsLength + ' S=' + r.chshSValue);
