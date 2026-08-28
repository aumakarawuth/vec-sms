/**
 * ประกาศ/ข่าวสารถึงนักศึกษา — รวมสองเมนูเดิมของศูนย์นักศึกษา
 * "การประชาสัมพันธ์" และ "ไปรษณีย์" เป็นระบบเดียว (ดูคอมเมนต์ที่ migration 0091)
 */
import { useState } from 'react';
import { api } from '../core/api';
import { thaiDateTime } from '../core/fmt';
import { href } from '../core/router';
import { ActionButton, AsyncView, Badge, Card, Field, PageHead, TableCard, useAsync } from '../ui/kit';

interface AnnouncementRow {
  id: string;
  title_th: string;
  category_th: string | null;
  published_at: string | null;
  expires_on: string | null;
  created_at: string;
  author_name: string;
}

export function AnnouncementsScreen() {
  const list = useAsync(() => api.get<AnnouncementRow[]>('/announcements'), []);

  return (
    <>
      <PageHead
        title="ประกาศ/ข่าวสารถึงนักศึกษา"
        sub="จัดทำประกาศ ตั้งเวลาเผยแพร่ และติดตามว่าฉบับไหนเป็นร่าง ฉบับไหนเผยแพร่แล้ว"
        actions={<a href={href('/student-center')}>← ศูนย์นักศึกษา</a>}
      />

      <NewAnnouncementCard onDone={list.reload} />

      <TableCard title="ประกาศทั้งหมด">
        <AsyncView state={list} empty="ยังไม่มีประกาศ — เพิ่มจากแบบฟอร์มด้านบน">
          {(rows) =>
            rows.length === 0 ? (
              <div className="empty">ยังไม่มีประกาศ — เพิ่มจากแบบฟอร์มด้านบน</div>
            ) : (
              <table>
                <thead>
                  <tr>
                    <th>ชื่อประกาศ</th>
                    <th style={{ width: 110 }}>หมวด</th>
                    <th style={{ width: 130 }}>สถานะ</th>
                    <th style={{ width: 150 }}>เผยแพร่เมื่อ</th>
                    <th style={{ width: 140 }}>ผู้เขียน</th>
                    <th style={{ width: 160 }} />
                  </tr>
                </thead>
                <tbody>
                  {rows.map((x) => (
                    <AnnouncementRowView key={x.id} row={x} onDone={list.reload} />
                  ))}
                </tbody>
              </table>
            )
          }
        </AsyncView>
      </TableCard>
    </>
  );
}

function NewAnnouncementCard({ onDone }: { onDone: () => void }) {
  const [titleTh, setTitleTh] = useState('');
  const [bodyTh, setBodyTh] = useState('');
  const [categoryTh, setCategoryTh] = useState('');
  const [expiresOn, setExpiresOn] = useState('');
  const [publishNow, setPublishNow] = useState(false);

  return (
    <Card title="สร้างประกาศใหม่">
      <div className="row">
        <Field label="ชื่อประกาศ">
          <input value={titleTh} onChange={(e) => setTitleTh(e.target.value)} style={{ minWidth: 320 }} />
        </Field>
        <Field label="หมวด">
          <input
            value={categoryTh}
            onChange={(e) => setCategoryTh(e.target.value)}
            placeholder="เช่น ทั่วไป การเงิน ตารางสอบ กิจกรรม"
          />
        </Field>
        <Field label="หมดอายุ (ไม่บังคับ)">
          <input type="date" value={expiresOn} onChange={(e) => setExpiresOn(e.target.value)} />
        </Field>
      </div>
      <div className="row">
        <Field label="เนื้อหาประกาศ">
          <textarea
            value={bodyTh}
            onChange={(e) => setBodyTh(e.target.value)}
            rows={4}
            style={{ width: '100%', minWidth: 400 }}
          />
        </Field>
      </div>
      <div className="row">
        <label className="field" style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
          <input type="checkbox" checked={publishNow} onChange={(e) => setPublishNow(e.target.checked)} />
          <span>เผยแพร่ทันที (ไม่ติ๊กจะบันทึกเป็นฉบับร่างก่อน)</span>
        </label>
      </div>
      <div className="row">
        <div className="shrink">
          <ActionButton
            className="primary"
            onRun={() => {
              if (!titleTh.trim() || !bodyTh.trim()) throw new Error('กรอกชื่อประกาศและเนื้อหาให้ครบ');
              return api.post('/announcements', {
                titleTh: titleTh.trim(),
                bodyTh: bodyTh.trim(),
                categoryTh: categoryTh.trim() || undefined,
                expiresOn: expiresOn || undefined,
                publishNow,
              });
            }}
            onDone={() => {
              setTitleTh('');
              setBodyTh('');
              setCategoryTh('');
              setExpiresOn('');
              setPublishNow(false);
              onDone();
            }}
          >
            บันทึก
          </ActionButton>
        </div>
      </div>
    </Card>
  );
}

function AnnouncementRowView({ row, onDone }: { row: AnnouncementRow; onDone: () => void }) {
  const isDraft = !row.published_at;
  const isExpired = !!row.expires_on && row.expires_on < new Date().toISOString().slice(0, 10);

  return (
    <tr>
      <td>{row.title_th}</td>
      <td>{row.category_th ?? '—'}</td>
      <td>
        {isDraft ? (
          <Badge kind="info">ฉบับร่าง</Badge>
        ) : isExpired ? (
          <Badge kind="warn">หมดอายุแล้ว</Badge>
        ) : (
          <Badge kind="ok">เผยแพร่แล้ว</Badge>
        )}
      </td>
      <td>{row.published_at ? thaiDateTime(row.published_at) : '—'}</td>
      <td>{row.author_name}</td>
      <td className="row" style={{ gap: 6 }}>
        {isDraft ? (
          <ActionButton toast onRun={() => api.post(`/announcements/${row.id}/publish`)} onDone={onDone}>
            เผยแพร่
          </ActionButton>
        ) : (
          <ActionButton toast onRun={() => api.post(`/announcements/${row.id}/unpublish`)} onDone={onDone}>
            ถอนเป็นร่าง
          </ActionButton>
        )}
        <ActionButton
          className="danger"
          toast
          confirm={`ลบประกาศ "${row.title_th}" ยืนยันหรือไม่`}
          onRun={() => api.del(`/announcements/${row.id}`)}
          onDone={onDone}
        >
          ลบ
        </ActionButton>
      </td>
    </tr>
  );
}
