import 'util.dart';
import 'db.dart';

Future<void> enqueue(String kind, Map<String, Object?> payload) =>
    q('insert into jobs(kind, payload) values(@k, @p:jsonb)', {'k': kind, 'p': payload});

/// Забирает одну задачу так, чтобы два обработчика не взяли одну и ту же.
/// light — лёгкие копии и вставки: у них своя очередь, чтобы не ждать сборки длинных роликов.
Future<Map<String, dynamic>?> claimJob({required bool light}) async {
  final row = await q1('''
    update jobs set status = 'running', started_at = now(), attempts = attempts + 1
    where id = (select id from jobs where status = 'queued'
                  and (kind in ('proxy', 'media', 'split')) = @light:boolean
                order by id for update skip locked limit 1)
    returning id, kind, payload''', {'light': light});
  if (row == null) return null;
  row['payload'] = jv(row['payload']);
  return row;
}

Future<void> finishJob(int id) =>
    q("update jobs set status = 'done', finished_at = now() where id = @id", {'id': id});

Future<void> failJob(int id, String error) => q(
    "update jobs set status = 'failed', error = @e, finished_at = now() where id = @id",
    {'id': id, 'e': error});

Future<void> requeueStuckJobs() => q("update jobs set status = 'queued' where status = 'running'");
