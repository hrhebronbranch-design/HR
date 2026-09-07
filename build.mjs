import { access } from "node:fs/promises";

await access("public/index.html");
console.log("Static HR app is ready in public/");
