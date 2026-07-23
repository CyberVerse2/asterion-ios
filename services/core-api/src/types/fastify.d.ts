import "fastify";

declare module "fastify" {
  interface FastifyRequest {
    _auth?: {
      clerkUserId: string;
    };
    auth: {
      clerkUserId: string;
    };
  }
}
