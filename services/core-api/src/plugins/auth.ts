import { createRemoteJWKSet, decodeJwt, jwtVerify } from "jose";
import type { FastifyReply, FastifyRequest } from "fastify";
import type { JWTVerifyOptions } from "jose";
import fp from "fastify-plugin";
import { env } from "../config/env";

type JwtPayload = {
  sub?: string;
  azp?: string;
  aud?: string | string[];
  iss?: string;
};

const clerkJwks = createRemoteJWKSet(new URL(env.CLERK_JWKS_URL));

/** Issuer URL → key set, for every Clerk instance whose tokens are accepted. */
const trustedIssuers = new Map([
  [normalizeIssuer(env.CLERK_ISSUER_URL), { issuer: env.CLERK_ISSUER_URL, jwks: clerkJwks }],
  ...env.CLERK_ADDITIONAL_ISSUERS.split(",")
    .map((value) => value.trim())
    .filter(Boolean)
    .map((issuer) => [
      normalizeIssuer(issuer),
      { issuer, jwks: createRemoteJWKSet(new URL(`${normalizeIssuer(issuer)}/.well-known/jwks.json`)) },
    ] as const),
]);

function normalizeIssuer(value: string): string {
  return value.replace(/\/+$/, "");
}

async function authenticate(request: FastifyRequest, reply: FastifyReply): Promise<void> {
  const authHeader = request.headers.authorization;
  const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;

  if (!token) {
    return reply.code(401).send({ error: "Missing bearer token." });
  }

  try {
    const decoded = decodeJwt(token) as JwtPayload;
    const trusted = decoded.iss ? trustedIssuers.get(normalizeIssuer(decoded.iss)) : undefined;
    if (!trusted) {
      return reply.code(401).send({ error: "Invalid or expired token." });
    }
    const verifyOptions: JWTVerifyOptions = {
      issuer: trusted.issuer,
    };
    if (env.CLERK_AUDIENCE && decoded.aud) {
      verifyOptions.audience = env.CLERK_AUDIENCE;
    } else if (env.CLERK_AUDIENCE && !decoded.aud) {
      request.log.info("Token missing aud claim; skipping audience check.");
    }
    const { payload } = await jwtVerify(token, trusted.jwks, verifyOptions);
    const jwtPayload = payload as JwtPayload;

    if (!jwtPayload.sub) {
      return reply.code(401).send({ error: "Invalid token subject." });
    }

    request.auth = { clerkUserId: jwtPayload.sub };
  } catch (error) {
    request.log.warn({ err: error }, "Clerk token verification failed.");
    return reply.code(401).send({ error: "Invalid or expired token." });
  }
}

export const authPlugin = fp(async (app) => {
  app.decorateRequest("auth", {
    getter(this: FastifyRequest) {
      return this._auth ?? { clerkUserId: "" };
    },
    setter(this: FastifyRequest, value: { clerkUserId: string }) {
      this._auth = value;
    },
  });
  app.decorate("authenticate", authenticate);
});

declare module "fastify" {
  interface FastifyInstance {
    authenticate: (request: FastifyRequest, reply: FastifyReply) => Promise<void>;
  }
}
