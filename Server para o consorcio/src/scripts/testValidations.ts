import * as fs from 'fs';

const tokens = JSON.parse(fs.readFileSync('test_tokens.json', 'utf8'));
const ATTACKER_TOKEN = tokens.attackerToken;
const BASE_URL = 'http://localhost:3000/api';

async function test(name: string, body: any) {
    const response = await fetch(`${BASE_URL}/bids`, {
        method: 'POST',
        headers: {
            'Authorization': `Bearer ${ATTACKER_TOKEN}`,
            'Content-Type': 'application/json'
        },
        body: JSON.stringify(body)
    });
    const data = await response.json();
    console.log(`${name}: ${response.status} - ${JSON.stringify(data)}`);
    return response.status;
}

async function main() {
    console.log('=== TESTANDO NOVAS VALIDAÇÕES ===\n');

    // Test 1: Tipo inválido
    console.log('1. Tipo inválido (HACKER_TYPE):');
    await test('', { subscriptionId: 'x', type: 'HACKER_TYPE', percentage: 50, amount: 5000 });

    // Test 2: Porcentagem negativa
    console.log('\n2. Porcentagem negativa (-50):');
    await test('', { subscriptionId: 'x', type: 'FREE', percentage: -50, amount: 5000 });

    // Test 3: Porcentagem acima de 100
    console.log('\n3. Porcentagem acima de 100 (150):');
    await test('', { subscriptionId: 'x', type: 'FREE', percentage: 150, amount: 5000 });

    // Test 4: Porcentagem extrema (100000)
    console.log('\n4. Porcentagem extrema (100000):');
    await test('', { subscriptionId: 'x', type: 'FREE', percentage: 100000, amount: 5000 });

    // Test 5: Valor negativo
    console.log('\n5. Valor negativo (-5000):');
    await test('', { subscriptionId: 'x', type: 'FREE', percentage: 50, amount: -5000 });

    // Test 6: Valor zero
    console.log('\n6. Valor zero:');
    await test('', { subscriptionId: 'x', type: 'FREE', percentage: 50, amount: 0 });

    // Test 7: Valores válidos (deve passar validação, falhar em contrato não encontrado)
    console.log('\n7. Valores válidos (deve dar 404 - contrato não encontrado):');
    await test('', { subscriptionId: 'x', type: 'FREE', percentage: 50, amount: 5000 });

    console.log('\n=== FIM DOS TESTES ===');
}

main();
