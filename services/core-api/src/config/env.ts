import { z } from "zod";

const envSchema = z.object({
  API_PORT: z.coerce.number().int().positive().default(3001),
  API_HOST: z.string().default("0.0.0.0"),
  DATABASE_URL: z.string().min(1),
  CLERK_ISSUER_URL: z.string().url(),
  CLERK_JWKS_URL: z.string().url(),
  CLERK_AUDIENCE: z.string().default(""),
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
});

export type AppEnv = z.infer<typeof envSchema>;

export const env: AppEnv = envSchema.parse(process.env);
