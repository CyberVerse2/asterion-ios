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

async function authenticate(request: FastifyRequest, reply: FastifyReply): Promise<void> {
  const authHeader = request.headers.authorization;
  const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;

  if (!token) {
    return reply.code(401).send({ error: "Missing bearer token." });
  }

  try {
    const decoded = decodeJwt(token) as JwtPayload;
    const verifyOptions: JWTVerifyOptions = {
      issuer: env.CLERK_ISSUER_URL,
    };
    if (env.CLERK_AUDIENCE && decoded.aud) {
      verifyOptions.audience = env.CLERK_AUDIENCE;
    } else if (env.CLERK_AUDIENCE && !decoded.aud) {
      request.log.info("Token missing aud claim; skipping audience check.");
    }
    const { payload } = await jwtVerify(token, clerkJwks, verifyOptions);
    const jwtPayload = payload as JwtPayload;

    if (!jwtPayload.sub) {
      return reply.code(401).send({ error: "Invalid token subject." });
    }

    request.auth = { clerkUserId: jwtPayload.sub };
  } catch (error) {
    request.log.warn({ error }, "Clerk token verification failed.");
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
