const test = require('node:test');
const assert = require('node:assert/strict');
const {buildSnapshot} = require('../snapshot_builder');
test('Renter snapshot excludes other bookings, slips, private fields, issues and logs', async () => {
 const tables = {
 users: [{user_id:1, name:'A',role:'customer',email:'a',phone:'123',bank_info:'bank',status:'active'}, {user_id:2,name:'B',role:'customer',email:'private',phone:'456',bank_info:'secret',status:'active'}],
 spaces: [{space_id:10,owner_id:3,status:'approved'}],
 bookings: [{booking_id:20,space_id:10,customer_id:2,start_date:'2026-12-01',app_status:'ownerReview'}],
 payments: [{payment_id:30,booking_id:20,image_data:'private'}],
 issues: [{reporter_id:2,subject:'private'}], admin_logs:[{details:'private'}]
 };
 const db = {query:async sql => [tables[(sql.match(/FROM\s+(\w+)/i)||[])[1]] || []]};
 const result = await buildSnapshot(db,1);
 assert.equal(result.users[1].email,'');
 assert.equal(result.users[1].phone,'');
 assert.equal(result.users[1].bank_info,'');
 for (const key of ['bookings','slips','issues','logs']) assert.deepEqual(result[key],[]);
 assert.equal(result.busy.length,1);
});
