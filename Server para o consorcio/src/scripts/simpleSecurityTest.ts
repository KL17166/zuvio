import * as fs from 'fs';

const tokens = JSON.parse(fs.readFileSync('test_tokens.json', 'utf8'));

const VICTIM_ID = tokens.victimId;
const ATTACKER_ID = tokens.attackerId;
const ATTACKER_TOKEN = tokens.attackerToken;

const BASE_URL = 'http://localhost:3000/api';

async function test(name: string, url: string, method: string = 'GET', body?: any) {
    const headers: Record<string, string> = {
        'Authorization': `Bearer ${ATTACKER_TOKEN}`,
        'Content-Type': 'application/json'
    };

    const options: RequestInit = { method, headers };
    if (body) options.body = JSON.stringify(body);

    const response = await fetch(url, options);
    const data = await response.json();

    return { status: response.status, data };
}

async function main() {
    console.log('=== SECURITY TEST RESULTS ===\n');

    // Test 1: IDOR
    console.log('1. IDOR: Attacker accessing VICTIM subscriptions');
    const r1 = await test('IDOR', `${BASE_URL}/subscriptions/${VICTIM_ID}`);
    console.log(`   Status: ${r1.status}`);
    console.log(`   Response: ${JSON.stringify(r1.data)}`);
    console.log(`   Result: ${r1.status === 403 ? '✅ BLOCKED' : '❌ VULNERABLE'}\n`);

    // Test 2: IDOR bids
    console.log('2. IDOR: Attacker accessing VICTIM bids');
    const r2 = await test('IDOR', `${BASE_URL}/bids/${VICTIM_ID}`);
    console.log(`   Status: ${r2.status}`);
    console.log(`   Response: ${JSON.stringify(r2.data)}`);
    console.log(`   Result: ${r2.status === 403 ? '✅ BLOCKED' : '❌ VULNERABLE'}\n`);

    // Test 3: Attacker accessing own data (should work)
    console.log('3. LEGIT: Attacker accessing OWN subscriptions');
    const r3 = await test('LEGIT', `${BASE_URL}/subscriptions/${ATTACKER_ID}`);
    console.log(`   Status: ${r3.status}`);
    console.log(`   Result: ${r3.status === 200 ? '✅ ALLOWED (correct)' : '⚠️ Unexpected'}\n`);

    // Test 4: XSS in login
    console.log('4. XSS: Script tag in CPF field');
    const r4 = await test('XSS', `${BASE_URL}/auth/login`, 'POST', {
        cpf: '<script>alert("XSS")</script>',
        password: 'test'
    });
    console.log(`   Status: ${r4.status}`);
    console.log(`   Response: ${JSON.stringify(r4.data).substring(0, 100)}`);
    const xssBlocked = !JSON.stringify(r4.data).includes('<script>');
    console.log(`   Result: ${xssBlocked ? '✅ SANITIZED/BLOCKED' : '❌ XSS REFLECTED'}\n`);

    // Test 5: SQL Injection
    console.log('5. SQLi: OR 1=1 in CPF');
    const r5 = await test('SQLi', `${BASE_URL}/auth/login`, 'POST', {
        cpf: "' OR '1'='1' --",
        password: 'test'
    });
    console.log(`   Status: ${r5.status}`);
    console.log(`   Response: ${JSON.stringify(r5.data).substring(0, 100)}`);
    console.log(`   Result: ${r5.status !== 200 ? '✅ BLOCKED' : '❌ VULNERABLE'}\n`);

    // Test 6: NoSQL Injection
    console.log('6. NoSQLi: Object injection in password');
    const r6 = await test('NoSQLi', `${BASE_URL}/auth/login`, 'POST', {
        cpf: '11111111111',
        password: { '$ne': null }
    });
    console.log(`   Status: ${r6.status}`);
    console.log(`   Response: ${JSON.stringify(r6.data).substring(0, 100)}`);
    console.log(`   Result: ${r6.status !== 200 ? '✅ BLOCKED' : '❌ VULNERABLE'}\n`);

    // Summary
    console.log('=== SUMMARY ===');
    const tests = [r1.status === 403, r2.status === 403, r3.status === 200, xssBlocked, r5.status !== 200, r6.status !== 200];
    const passed = tests.filter(t => t).length;
    console.log(`Passed: ${passed}/${tests.length}`);
    console.log(passed === tests.length ? '🔒 ALL SECURITY TESTS PASSED!' : '⚠️ SOME VULNERABILITIES FOUND');
}

main().catch(console.error);
