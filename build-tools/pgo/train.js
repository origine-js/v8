// Focused builtin-PGO training, not a performance benchmark. All objects are
// workload-owned and may be reclaimed after their promises/iterators settle.
"use strict";

let hookEvents = 0;

// Receives borrowed promise locals during the hook; retains nothing.
function hook() { hookEvents++; }

// Returns the copied primitive argument; retains nothing.
function identity(value) { return value; }

// Borrows the resolve callback through this synchronous invocation.
function resolveExecutor(resolve) { resolve(17); }

// Borrows callbacks through this synchronous invocation; rejects with a primitive.
function rejectExecutor(_resolve, reject) { reject(7); }

// Borrows callbacks and this until return; settles with this object's primitive.
function thenable(resolve, reject) {
  if (this.reject) reject(this.value);
  else resolve(this.value);
}

// Owns its promise until settlement; retains only copied primitive inputs.
async function awaited(value) {
  const first = await value;
  return await Promise.resolve(first + 1);
}

// Owns a handled rejection until settlement and returns its copied reason.
async function handledRejection(value) {
  try { return await Promise.reject(value); }
  catch (reason) { return reason; }
}

// The caller owns this iterator; copied primitives live until it closes.
async function* sequence(value) {
  const first = await Promise.resolve(value);
  yield first;
  yield Promise.resolve(first + 1);
  yield await Promise.resolve(first + 2);
  return first + 3;
}

// The caller owns this iterator and must consume the rejected next() promise.
async function* rejectedSequence(value) { yield Promise.reject(value); }

// Instances and their chains are workload-owned until settlement.
class DerivedPromise extends Promise {}

// Owns temporary buffers/views through return and returns a copied checksum.
function arrays(value) {
  const lengths = [0, 8, 16, 64, 256, 4096];
  const bytes = new Uint8Array(lengths[value % lengths.length]);
  bytes.fill(value & 255);
  const numbers = new Float64Array([value, value + 1, value + 2]);
  const copied = new Uint16Array(bytes);
  const view = new Uint32Array(new ArrayBuffer(64), 4, 4);
  const shared = new Int32Array(new SharedArrayBuffer(64), 0, 8);
  const resizable = new ArrayBuffer(32, {maxByteLength: 128});
  const tracking = new Uint8Array(resizable);
  resizable.resize(64);
  const iterable = new Uint16Array([value, value + 1].values());
  const arrayLike = new Uint32Array({0: value, 1: value + 1, length: 2});
  let result = bytes.length + numbers[0] + copied.length + view.length +
    shared.length + tracking.length + iterable[0] + arrayLike[1];
  if ((value & 255) === 0) {
    try { new Uint8Array(-1); }
    catch (error) {
      if (!(error instanceof RangeError)) throw error;
      result++;
    }
  }
  return result;
}

// Owns and awaits every promise/iterator it creates; returns a primitive checksum.
async function phase(iterations) {
  let checksum = 0;
  for (let index = 0; index < iterations; index++) {
    checksum += await awaited(index);
    checksum += await new Promise(resolveExecutor).then(identity);
    checksum += await new Promise(rejectExecutor).catch(identity);
    checksum += await Promise.resolve(index).then(identity);
    checksum += await handledRejection(index);
    if ((index & 7) === 0) {
      checksum += await {then: thenable, value: index, reject: false};
      try { await {then: thenable, value: index, reject: true}; }
      catch (reason) { checksum += reason; }
      const values = await DerivedPromise.all([index, Promise.resolve(index + 1)]);
      checksum += values[0] + values[1];
      checksum += await DerivedPromise.resolve(index).then(identity);
    }
    const iterator = sequence(index);
    checksum += (await iterator.next()).value;
    checksum += (await iterator.next()).value;
    if ((index & 3) === 0) {
      checksum += (await iterator.next()).value;
      checksum += (await iterator.next()).value;
    } else {
      checksum += (await iterator.return(Promise.resolve(index + 4))).value;
    }
    if ((index & 15) === 0) {
      const rejected = rejectedSequence(index);
      try { await rejected.next(); }
      catch (reason) { checksum += reason; }
      const closing = sequence(index);
      await closing.next();
      try { await closing.return(Promise.reject(index)); }
      catch (reason) { checksum += reason; }
    }
    checksum += arrays(index);
  }
  return checksum;
}

// Owns both training phases, drains their async work, and clears all context hooks.
async function main(iterations) {
  if (!Object.isFrozen(Promise.prototype) || !Object.isFrozen(Array.prototype) ||
      typeof Date.parse !== "undefined") {
    throw new Error("PGO training must run with the production hardening");
  }
  const ordinary = await phase(iterations);
  d8.promise.setHooks(hook, hook, hook, hook);
  let hooked;
  try { hooked = await phase(iterations); }
  finally { d8.promise.setHooks(); }
  if (ordinary !== hooked || !Number.isFinite(ordinary) || hookEvents === 0) {
    throw new Error("Training workload did not complete consistently");
  }
  print(JSON.stringify({iterationsPerPhase: iterations, ordinary, hooked, hookEvents}));
}

// Borrows an error through return; exits the training process on failure.
function failed(error) {
  print(String(error && error.stack || error));
  quit(1);
}

const iterations = Number(arguments[0] || 8000);
if (!Number.isSafeInteger(iterations) || iterations < 1000) {
  throw new Error("Training requires at least 1000 iterations per phase");
}
main(iterations).catch(failed);
