/*
  Warnings:

  - You are about to drop the column `idToken` on the `installments` table. All the data in the column will be lost.
  - A unique constraint covering the columns `[idTokenPay]` on the table `installments` will be added. If there are existing duplicate values, this will fail.
  - The required column `idTokenPay` was added to the `installments` table with a prisma-level default value. This is not possible if the table is not empty. Please add this column as optional, then populate it before making it required.

*/
-- DropIndex
DROP INDEX "installments_idToken_idx";

-- DropIndex
DROP INDEX "installments_idToken_key";

-- AlterTable
ALTER TABLE "installments" DROP COLUMN "idToken",
ADD COLUMN     "idTokenPay" TEXT NOT NULL;

-- CreateIndex
CREATE UNIQUE INDEX "installments_idTokenPay_key" ON "installments"("idTokenPay");

-- CreateIndex
CREATE INDEX "installments_idTokenPay_idx" ON "installments"("idTokenPay");
