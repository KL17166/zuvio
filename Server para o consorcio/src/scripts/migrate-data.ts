/**
 * Migration Script: SQLite → PostgreSQL
 * 
 * Reads data from the old SQLite database (dev.db) and inserts it into
 * the new PostgreSQL database. Run this once after setting up PostgreSQL.
 * 
 * Usage: npx ts-node src/scripts/migrate-data.ts
 */

import { PrismaClient as PgPrismaClient } from '@prisma/client';
import Database from 'better-sqlite3';
import path from 'path';

const SQLITE_PATH = path.join(__dirname, '../../prisma/dev.db');

async function migrate() {
    console.log('🔄 Starting SQLite → PostgreSQL migration...\n');

    // Connect to PostgreSQL (uses current DATABASE_URL from .env)
    const pg = new PgPrismaClient();

    // Connect to old SQLite
    let sqlite: any;
    try {
        sqlite = new Database(SQLITE_PATH, { readonly: true });
    } catch (err) {
        console.log('⚠️  SQLite database not found at:', SQLITE_PATH);
        console.log('   Nothing to migrate — starting fresh with PostgreSQL.');
        await pg.$disconnect();
        return;
    }

    try {
        // 1. Users
        const users = sqlite.prepare('SELECT * FROM users').all();
        console.log(`📋 Users: ${users.length} records`);
        for (const u of users) {
            await pg.user.upsert({
                where: { id: u.id },
                create: {
                    id: u.id, name: u.name, email: u.email, cpf: u.cpf,
                    birthDate: u.birthDate ? new Date(u.birthDate) : null,
                    phone: u.phone, passwordHash: u.passwordHash, role: u.role,
                    address: u.address, documentFrontUrl: u.documentFrontUrl,
                    documentBackUrl: u.documentBackUrl, selfieUrl: u.selfieUrl,
                    createdAt: new Date(u.createdAt), updatedAt: new Date(u.updatedAt),
                },
                update: {},
            });
        }

        // 2. Products
        const products = sqlite.prepare('SELECT * FROM products').all();
        console.log(`📋 Products: ${products.length} records`);
        for (const p of products) {
            await pg.product.upsert({
                where: { id: p.id },
                create: {
                    id: p.id, name: p.name, description: p.description, type: p.type,
                    category: p.category, imageUrl: p.imageUrl, imageUrls: p.imageUrls,
                    price: p.price, active: Boolean(p.active), isFeatured: Boolean(p.isFeatured),
                    isPopular: Boolean(p.isPopular), brand: p.brand, model: p.model, year: p.year,
                    specs: p.specs, minDuration: p.minDuration, maxDuration: p.maxDuration,
                    adminFeeRate: p.adminFeeRate,
                    createdAt: new Date(p.createdAt), updatedAt: new Date(p.updatedAt),
                },
                update: {},
            });
        }

        // 3. ConsortiumPlans
        const plans = sqlite.prepare('SELECT * FROM consortium_plans').all();
        console.log(`📋 Plans: ${plans.length} records`);
        for (const p of plans) {
            await pg.consortiumPlan.upsert({
                where: { id: p.id },
                create: {
                    id: p.id, name: p.name, durationMonths: p.durationMonths,
                    adminFeeRate: p.adminFeeRate, fundRate: p.fundRate,
                    productId: p.productId, active: Boolean(p.active),
                },
                update: {},
            });
        }

        // 4. Subscriptions
        const subs = sqlite.prepare('SELECT * FROM subscriptions').all();
        console.log(`📋 Subscriptions: ${subs.length} records`);
        for (const s of subs) {
            await pg.subscription.upsert({
                where: { id: s.id },
                create: {
                    id: s.id, userId: s.userId, planId: s.planId,
                    groupNumber: s.groupNumber, quotaNumber: s.quotaNumber,
                    creditValue: s.creditValue, status: s.status,
                    contemplated: Boolean(s.contemplated),
                    contemplationDate: s.contemplationDate ? new Date(s.contemplationDate) : null,
                    contemplatedDate: s.contemplatedDate ? new Date(s.contemplatedDate) : null,
                    contemplationType: s.contemplationType,
                    termsAccepted: Boolean(s.termsAccepted),
                    termsAcceptedAt: s.termsAcceptedAt ? new Date(s.termsAcceptedAt) : null,
                    termsIpAddress: s.termsIpAddress,
                    balanceDue: s.balanceDue, paidInstallments: s.paidInstallments,
                    totalInstallments: s.totalInstallments,
                    createdAt: new Date(s.createdAt), updatedAt: new Date(s.updatedAt),
                },
                update: {},
            });
        }

        // 5. Installments
        const installments = sqlite.prepare('SELECT * FROM installments').all();
        console.log(`📋 Installments: ${installments.length} records`);
        for (const i of installments) {
            await pg.installment.upsert({
                where: { id: i.id },
                create: {
                    id: i.id, subscriptionId: i.subscriptionId, number: i.number,
                    amount: i.amount, dueDate: new Date(i.dueDate), status: i.status,
                    paymentDate: i.paymentDate ? new Date(i.paymentDate) : null,
                    paymentMethod: i.paymentMethod,
                    createdAt: new Date(i.createdAt), updatedAt: new Date(i.updatedAt),
                },
                update: {},
            });
        }

        // 6. Bids
        const bids = sqlite.prepare('SELECT * FROM bids').all();
        console.log(`📋 Bids: ${bids.length} records`);
        for (const b of bids) {
            await pg.bid.upsert({
                where: { id: b.id },
                create: {
                    id: b.id, subscriptionId: b.subscriptionId, type: b.type,
                    percentage: b.percentage, amount: b.amount, status: b.status,
                    isWinner: Boolean(b.isWinner),
                    drawDate: b.drawDate ? new Date(b.drawDate) : null,
                    contemplatedDate: b.contemplatedDate ? new Date(b.contemplatedDate) : null,
                    createdAt: new Date(b.createdAt), updatedAt: new Date(b.updatedAt),
                },
                update: {},
            });
        }

        // 7. AuditLogs
        const logs = sqlite.prepare('SELECT * FROM audit_logs').all();
        console.log(`📋 AuditLogs: ${logs.length} records`);
        for (const l of logs) {
            await pg.auditLog.upsert({
                where: { id: l.id },
                create: {
                    id: l.id, userId: l.userId, action: l.action,
                    resource: l.resource, details: l.details,
                    ipAddress: l.ipAddress, timestamp: new Date(l.timestamp),
                },
                update: {},
            });
        }

        // 8. GatewayConfigs
        const gateways = sqlite.prepare('SELECT * FROM gateway_configs').all();
        console.log(`📋 GatewayConfigs: ${gateways.length} records`);
        for (const g of gateways) {
            await pg.gatewayConfig.upsert({
                where: { id: g.id },
                create: {
                    id: g.id, name: g.name, displayName: g.displayName,
                    enabled: Boolean(g.enabled), apiKey: g.apiKey, apiSecret: g.apiSecret,
                    webhookSecret: g.webhookSecret, baseUrl: g.baseUrl,
                    environment: g.environment, platformId: g.platformId,
                    supportsPix: Boolean(g.supportsPix), supportsBoleto: Boolean(g.supportsBoleto),
                    supportsCard: Boolean(g.supportsCard), isDefaultPix: Boolean(g.isDefaultPix),
                    isDefaultBoleto: Boolean(g.isDefaultBoleto), isDefaultCard: Boolean(g.isDefaultCard),
                    createdAt: new Date(g.createdAt), updatedAt: new Date(g.updatedAt),
                },
                update: {},
            });
        }

        // 9. SecurityThreats + BlockedDevices + WebhookLogs
        try {
            const threats = sqlite.prepare('SELECT * FROM security_threats').all();
            console.log(`📋 SecurityThreats: ${threats.length} records`);
            for (const t of threats) {
                await pg.securityThreat.upsert({
                    where: { id: t.id },
                    create: {
                        id: t.id, ipAddress: t.ipAddress, deviceId: t.deviceId,
                        deviceModel: t.deviceModel, userId: t.userId, threatType: t.threatType,
                        threatScore: t.threatScore, requestPath: t.requestPath,
                        requestMethod: t.requestMethod, userAgent: t.userAgent,
                        details: t.details, blocked: Boolean(t.blocked),
                        createdAt: new Date(t.createdAt),
                    },
                    update: {},
                });
            }
        } catch { console.log('   (SecurityThreats table not found, skipping)'); }

        try {
            const blocked = sqlite.prepare('SELECT * FROM blocked_devices').all();
            console.log(`📋 BlockedDevices: ${blocked.length} records`);
            for (const b of blocked) {
                await pg.blockedDevice.upsert({
                    where: { id: b.id },
                    create: {
                        id: b.id, deviceId: b.deviceId, ipAddress: b.ipAddress,
                        reason: b.reason, threatScore: b.threatScore,
                        permanent: Boolean(b.permanent), active: Boolean(b.active),
                        unblockedAt: b.unblockedAt ? new Date(b.unblockedAt) : null,
                        unblockedBy: b.unblockedBy, blockedAt: new Date(b.blockedAt),
                    },
                    update: {},
                });
            }
        } catch { console.log('   (BlockedDevices table not found, skipping)'); }

        try {
            const webhookLogs = sqlite.prepare('SELECT * FROM webhook_logs').all();
            console.log(`📋 WebhookLogs: ${webhookLogs.length} records`);
            for (const w of webhookLogs) {
                await pg.webhookLog.upsert({
                    where: { id: w.id },
                    create: {
                        id: w.id, signature: w.signature, provider: w.provider,
                        payload: w.payload, processedAt: new Date(w.processedAt),
                    },
                    update: {},
                });
            }
        } catch { console.log('   (WebhookLogs table not found, skipping)'); }

        console.log('\n✅ Migration complete! All data transferred to PostgreSQL.');
    } catch (err) {
        console.error('\n❌ Migration error:', err);
    } finally {
        sqlite.close();
        await pg.$disconnect();
    }
}

migrate();
