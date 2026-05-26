import * as fs from 'fs';

const tokens = JSON.parse(fs.readFileSync('test_tokens.json', 'utf8'));

const VICTIM_ID = tokens.victimId;
const ATTACKER_TOKEN = tokens.attackerToken;

const BASE_URL = 'http://localhost:3000/api';

interface TestResult {
    test: string;
    attack: string;
    expected: string;
    actual: string;
    passed: boolean;
}

const results: TestResult[] = [];

async function runTest(name: string, attack: string, expected: string, url: string, method: string = 'GET', body?: any) {
    try {
        const headers: Record<string, string> = {
            'Authorization': `Bearer ${ATTACKER_TOKEN}`,
            'Content-Type': 'application/json'
        };

        const options: RequestInit = { method, headers };
        if (body) options.body = JSON.stringify(body);

        const response = await fetch(url, options);
        const data = await response.json();

        const actualStatus = `${response.status}`;
        const passed = actualStatus === expected ||
            (expected === '403' && (response.status === 403 || response.status === 401)) ||
            (expected.includes('sanitized') && !JSON.stringify(data).includes('<script>'));

        results.push({
            test: name,
            attack: attack,
            expected: expected,
            actual: `${response.status} - ${JSON.stringify(data).substring(0, 80)}`,
            passed
        });

        console.log(`${passed ? '✅' : '❌'} ${name}`);
        console.log(`   Attack: ${attack}`);
        console.log(`   Response: ${response.status} - ${JSON.stringify(data).substring(0, 100)}`);
        console.log('');
    } catch (e: any) {
        console.log(`❌ ${name} - Error: ${e.message}`);
        results.push({
            test: name, attack, expected, actual: `Error: ${e.message}`, passed: false
        });
    }
}

async function main() {
    console.log('🔓 === ADVANCED SECURITY TESTS ===\n');
    console.log(`Attacker Token: ${ATTACKER_TOKEN.substring(0, 50)}...`);
    console.log(`Victim ID: ${VICTIM_ID}\n`);

    // === TEST 1: IDOR - Access victim's subscriptions ===
    await runTest(
        'IDOR: Access victim subscriptions',
        'Attacker with valid token tries to access VICTIM\'s subscriptions',
        '403',
        `${BASE_URL}/subscriptions/${VICTIM_ID}`
    );

    // === TEST 2: IDOR - Access victim's bids ===
    await runTest(
        'IDOR: Access victim bids',
        'Attacker with valid token tries to access VICTIM\'s bids',
        '403',
        `${BASE_URL}/bids/${VICTIM_ID}`
    );

    // === TEST 3: XSS Injection in registration ===
    await runTest(
        'XSS: Script injection in name',
        'Register with <script>alert("XSS")</script> as name',
        '400',
        `${BASE_URL}/auth/register`,
        'POST',
        {
            name: '<script>alert("XSS")</script>',
            email: 'xss@test.com',
            cpf: '33333333333',
            password: 'TestPass123',
            birthDate: '1990-01-01'
        }
    );

    // === TEST 4: SQL Injection attempt ===
    await runTest(
        'SQLi: OR 1=1 injection in CPF',
        'Login with CPF = "\' OR \'1\'=\'1"',
        '400',
        `${BASE_URL}/auth/login`,
        'POST',
        {
            cpf: "' OR '1'='1",
            password: 'anything'
        }
    );

    // === TEST 5: NoSQL Injection attempt ===
    await runTest(
        'NoSQLi: Object injection in password',
        'Login with password = {"$ne": null}',
        '401',
        `${BASE_URL}/auth/login`,
        'POST',
        {
            cpf: '11111111111',
            password: { '$ne': null }
        }
    );

    // === TEST 6: Create bid for victim's subscription ===
    await runTest(
        'IDOR: Create bid for victim subscription',
        'Attacker tries to create bid for subscription they don\'t own',
        '403',
        `${BASE_URL}/bids`,
        'POST',
        {
            subscriptionId: 'victim-subscription-id',
            type: 'FREE',
            percentage: 50,
            amount: 5000
        }
    );

    // === TEST 7: XSS in bid type ===
    await runTest(
        'XSS: Injection in bid type field',
        'Create bid with type = <img src=x onerror=alert(1)>',
        '403',
        `${BASE_URL}/bids`,
        'POST',
        {
            subscriptionId: 'any-id',
            type: '<img src=x onerror=alert(1)>',
            percentage: 50,
            amount: 5000
        }
    );

    // === SUMMARY ===
    console.log('\n📊 === TEST SUMMARY ===\n');
    const passed = results.filter(r => r.passed).length;
    const failed = results.filter(r => !r.passed).length;

    console.log(`✅ Passed: ${passed}`);
    console.log(`❌ Failed: ${failed}`);
    console.log(`Total: ${results.length}`);

    if (failed === 0) {
        console.log('\n🔒 ALL SECURITY TESTS PASSED!');
    } else {
        console.log('\n⚠️ SOME TESTS FAILED - Review needed');
        results.filter(r => !r.passed).forEach(r => {
            console.log(`  - ${r.test}: ${r.actual}`);
        });
    }
}

main();
